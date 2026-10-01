CREATE OR REPLACE FUNCTION sg_insert_reifier_hcl_subgraph(
    p_tx_id uuid,
    p_cone_depth int,
    p_blast_depth int
) RETURNS int AS $$
DECLARE
    _new_rows int;
    _node_count int;
    _i int;
BEGIN
    -- Clear old subgraph entries for this tx
    DELETE FROM transaction_subgraphs
    WHERE tx_id = p_tx_id AND node_type = 'hcl';
    -- Materialize tx_hcl into a temp table
    CREATE TEMP TABLE _sg_tx_hcl ON COMMIT DROP AS
    SELECT
        tl.state_id,
        (tl.data->>'node_id')::text AS id,
        (tl.data->>'address')::text AS address,
        coalesce(
            (SELECT array_agg(e) FROM jsonb_array_elements_text(tl.data->'refs') AS e),
            '{}'::text[]
        ) AS refs,
        CASE WHEN tl.data ? 'remote_tf_state_refs'
            THEN tl.data->'remote_tf_state_refs'
            ELSE null
        END AS remote_tf_state_refs,
        (tl.data->>'remote_state')::uuid AS remote_state_id
    FROM transaction_logs AS tl
    WHERE tl.tx_id = p_tx_id
      AND tl.action = 'hcl_set'
      AND tl.object_type = 'hcl';
    CREATE INDEX ON _sg_tx_hcl (state_id, id);
    CREATE INDEX ON _sg_tx_hcl (state_id, address);
    -- Materialize tx_deletes
    CREATE TEMP TABLE _sg_tx_deletes ON COMMIT DROP AS
    SELECT tl.state_id, (tl.data->>'node_id')::text AS id
    FROM transaction_logs AS tl
    WHERE tl.tx_id = p_tx_id
      AND tl.action = 'hcl_delete'
      AND tl.object_type = 'hcl';
    CREATE INDEX ON _sg_tx_deletes (state_id, id);
    -- Visited set: each (state_id, id) is processed at most once
    CREATE TEMP TABLE _sg_visited (
        state_id uuid NOT NULL,
        id text NOT NULL,
        refs text[] NOT NULL,
        address text NOT NULL,
        direction text NOT NULL,
        depth int NOT NULL,
        processed boolean NOT NULL DEFAULT false,
        PRIMARY KEY (state_id, id)
    ) ON COMMIT DROP;
    -- Insert seeds from tx_hcl
    INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
    SELECT t.state_id, t.id, t.refs, t.address, 'seed', 0
    FROM _sg_tx_hcl AS t
    ON CONFLICT (state_id, id) DO NOTHING;
    -- Insert remote_ref_seeds with direction='cone', depth=1
    INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
    SELECT
        coalesce(tx.state_id, h.state_id),
        coalesce(tx.id, h.id),
        coalesce(tx.refs, h.refs),
        coalesce(tx.address, h.address),
        'cone',
        1
    FROM _sg_tx_hcl AS seed
    CROSS JOIN LATERAL jsonb_each(seed.remote_tf_state_refs) AS kv(key, value)
    CROSS JOIN LATERAL jsonb_array_elements_text(kv.value) AS ref_val(ref)
    INNER JOIN LATERAL (
        SELECT remote_state_id
        FROM (
            SELECT ds_tx.remote_state_id, 'a' AS priority
            FROM _sg_tx_hcl AS ds_tx
            WHERE ds_tx.state_id = seed.state_id
              AND ds_tx.address = kv.key
              AND ds_tx.remote_state_id IS NOT NULL
            UNION ALL
            SELECT ds.remote_state_id, 'b' AS priority
            FROM hcl AS ds
            WHERE ds.state_id = seed.state_id
              AND ds.address = kv.key
              AND ds.remote_state_id IS NOT NULL
        ) AS candidates
        ORDER BY priority
        LIMIT 1
    ) AS resolved ON true
    LEFT JOIN _sg_tx_hcl AS tx
        ON tx.state_id = resolved.remote_state_id
        AND tx.address = ref_val.ref
    LEFT JOIN LATERAL (
        SELECT h2.state_id, h2.id, h2.refs, h2.address
        FROM hcl AS h2
        WHERE h2.state_id = resolved.remote_state_id
          AND h2.address = ref_val.ref
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_hcl t2 WHERE t2.state_id = h2.state_id AND t2.id = h2.id)
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_deletes td WHERE td.state_id = h2.state_id AND td.id = h2.id)
    ) AS h ON tx.id IS NULL
    WHERE seed.remote_tf_state_refs IS NOT NULL
      AND (tx.id IS NOT NULL OR h.id IS NOT NULL)
    ON CONFLICT (state_id, id) DO NOTHING;
    -- Cone expansion loop
    IF p_cone_depth > 0 THEN
        FOR _i IN 1..p_cone_depth LOOP
            -- 1. Same-state cone: find referenced node in the transaction
            INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
            SELECT DISTINCT
                v.state_id,
                tx.id,
                tx.refs,
                tx.address,
                'cone',
                v.depth + 1
            FROM _sg_visited AS v
            CROSS JOIN LATERAL unnest(v.refs) AS ref_addr(addr)
            INNER JOIN _sg_tx_hcl AS tx
                ON tx.state_id = v.state_id
                AND tx.address = ref_addr.addr
            WHERE NOT v.processed
              AND v.direction IN ('seed', 'cone')
            ON CONFLICT (state_id, id) DO NOTHING;
            -- 2. Same-state cone: find referenced node in committed data
            INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
            SELECT DISTINCT
                v.state_id,
                h.id,
                h.refs,
                h.address,
                'cone',
                v.depth + 1
            FROM _sg_visited AS v
            CROSS JOIN LATERAL unnest(v.refs) AS ref_addr(addr)
            CROSS JOIN LATERAL (
                SELECT h2.id, h2.refs, h2.address, h2.state_id
                FROM hcl AS h2
                WHERE h2.state_id = v.state_id
                  AND h2.address = ref_addr.addr
            ) AS h
            WHERE NOT v.processed
              AND v.direction IN ('seed', 'cone')
              AND NOT EXISTS (SELECT 1 FROM _sg_tx_hcl tx2 WHERE tx2.state_id = h.state_id AND tx2.id = h.id)
              AND NOT EXISTS (SELECT 1 FROM _sg_tx_deletes txd WHERE txd.state_id = h.state_id AND txd.id = h.id)
            ON CONFLICT (state_id, id) DO NOTHING;
            -- 3. Cross-state cone: find target in the transaction
            INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
            SELECT DISTINCT
                tx.state_id,
                tx.id,
                tx.refs,
                tx.address,
                'cone',
                v.depth + 1
            FROM _sg_visited AS v
            INNER JOIN hcl_refs AS hr
                ON hr.state_id = v.state_id AND hr.id = v.id AND hr.ref_state_id IS NOT NULL
            INNER JOIN _sg_tx_hcl AS tx
                ON tx.state_id = hr.ref_state_id
                AND tx.address = hr.ref
            WHERE NOT v.processed
              AND v.direction IN ('seed', 'cone')
            ON CONFLICT (state_id, id) DO NOTHING;
            -- 4. Cross-state cone: find target in committed data
            INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
            SELECT DISTINCT
                h.state_id,
                h.id,
                h.refs,
                h.address,
                'cone',
                v.depth + 1
            FROM _sg_visited AS v
            INNER JOIN hcl_refs AS hr
                ON hr.state_id = v.state_id AND hr.id = v.id AND hr.ref_state_id IS NOT NULL
            CROSS JOIN LATERAL (
                SELECT h2.id, h2.refs, h2.address, h2.state_id
                FROM hcl AS h2
                WHERE h2.state_id = hr.ref_state_id
                  AND h2.address = hr.ref
            ) AS h
            WHERE NOT v.processed
              AND v.direction IN ('seed', 'cone')
              AND NOT EXISTS (SELECT 1 FROM _sg_tx_hcl tx2 WHERE tx2.state_id = h.state_id AND tx2.id = h.id)
              AND NOT EXISTS (SELECT 1 FROM _sg_tx_deletes txd WHERE txd.state_id = h.state_id AND txd.id = h.id)
            ON CONFLICT (state_id, id) DO NOTHING;
            -- Mark cone nodes as processed
            UPDATE _sg_visited SET processed = true
            WHERE NOT processed AND direction IN ('seed', 'cone');
            -- Check if we added anything new
            GET DIAGNOSTICS _new_rows = ROW_COUNT;
        END LOOP;
    ELSE
        -- Even with cone_depth=0, mark seeds as processed for blast phase
        UPDATE _sg_visited SET processed = true WHERE NOT processed;
    END IF;
    -- Reset processed for blast phase so seeds+cone nodes can be blast sources
    UPDATE _sg_visited SET processed = false;
    -- Blast expansion loop
    FOR _i IN 1..p_blast_depth LOOP
        -- 5. Same-state blast: find dependents in the transaction
        INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
        SELECT DISTINCT
            v.state_id,
            tx.id,
            tx.refs,
            tx.address,
            'blast',
            _i
        FROM _sg_visited AS v
        INNER JOIN _sg_tx_hcl AS tx
            ON tx.state_id = v.state_id
            AND v.address = any(tx.refs)
        WHERE NOT v.processed
        ON CONFLICT (state_id, id) DO NOTHING;
        -- 6. Same-state blast: find dependents in committed data via hcl_refs
        INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
        SELECT DISTINCT
            h.state_id,
            h.id,
            h.refs,
            h.address,
            'blast',
            _i
        FROM _sg_visited AS v
        INNER JOIN hcl_refs AS hr
            ON hr.state_id = v.state_id AND hr.ref = v.address
        CROSS JOIN LATERAL (
            SELECT h2.id, h2.refs, h2.address, h2.state_id
            FROM hcl AS h2
            WHERE h2.state_id = hr.state_id AND h2.id = hr.id
            OFFSET 0
        ) AS h
        WHERE NOT v.processed
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_hcl tx2 WHERE tx2.state_id = h.state_id AND tx2.id = h.id)
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_deletes txd WHERE txd.state_id = h.state_id AND txd.id = h.id)
        ON CONFLICT (state_id, id) DO NOTHING;
        -- 7. Cross-state blast: find dependents in the transaction in OTHER states
        INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
        SELECT DISTINCT
            tx.state_id,
            tx.id,
            tx.refs,
            tx.address,
            'blast',
            _i
        FROM _sg_visited AS v
        INNER JOIN hcl_refs AS hr
            ON hr.ref_state_id = v.state_id AND hr.ref = v.address AND hr.ref_state_id IS NOT NULL
        INNER JOIN _sg_tx_hcl AS tx
            ON tx.state_id = hr.state_id AND tx.id = hr.id
        WHERE NOT v.processed
        ON CONFLICT (state_id, id) DO NOTHING;
        -- 8. Cross-state blast: find dependents in committed data
        INSERT INTO _sg_visited (state_id, id, refs, address, direction, depth)
        SELECT DISTINCT
            h.state_id,
            h.id,
            h.refs,
            h.address,
            'blast',
            _i
        FROM _sg_visited AS v
        INNER JOIN hcl_refs AS hr
            ON hr.ref_state_id = v.state_id AND hr.ref = v.address AND hr.ref_state_id IS NOT NULL
        CROSS JOIN LATERAL (
            SELECT h2.id, h2.refs, h2.address, h2.state_id
            FROM hcl AS h2
            WHERE h2.state_id = hr.state_id AND h2.id = hr.id
        ) AS h
        WHERE NOT v.processed
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_hcl tx2 WHERE tx2.state_id = h.state_id AND tx2.id = h.id)
          AND NOT EXISTS (SELECT 1 FROM _sg_tx_deletes txd WHERE txd.state_id = h.state_id AND txd.id = h.id)
        ON CONFLICT (state_id, id) DO NOTHING;
        -- Mark blast nodes as processed
        UPDATE _sg_visited SET processed = true WHERE NOT processed;
    END LOOP;
    -- Remove deleted nodes
    DELETE FROM _sg_visited AS v
    USING _sg_tx_deletes AS td
    WHERE v.state_id = td.state_id AND v.id = td.id;
    -- Insert results into transaction_subgraphs
    INSERT INTO transaction_subgraphs (tx_id, state_id, item, node_type, direction, depth)
    SELECT
        p_tx_id,
        v.state_id,
        jsonb_build_object('node_id', v.id),
        'hcl',
        v.direction,
        v.depth
    FROM _sg_visited AS v;
    GET DIAGNOSTICS _node_count = ROW_COUNT;
    RETURN _node_count;
END;
$$ LANGUAGE plpgsql;
