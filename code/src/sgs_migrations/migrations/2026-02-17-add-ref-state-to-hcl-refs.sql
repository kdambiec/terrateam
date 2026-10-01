alter table hcl
  add column remote_tf_state_refs jsonb;

alter table hcl_refs
  add column ref_state_id uuid;

create or replace function sync_hcl_refs()
returns trigger
language plpgsql
as $$
declare
  ds_key text;
  ds_value jsonb;
  remote_state_id uuid;
  ref_item text;
begin
  -- Delete local refs that were removed
  delete from hcl_refs r
  where r.state_id = new.state_id
    and r.id = new.id
    and r.ref_state_id is null
    and not (r.ref = any (new.refs));
  -- Insert new local refs that do not yet exist
  insert into hcl_refs (state_id, id, ref)
  select new.state_id, new.id, ref
  from unnest(new.refs) as ref
  on conflict do nothing;
  -- Delete all remote refs (fully replaced each sync)
  delete from hcl_refs r
  where r.state_id = new.state_id
    and r.id = new.id
    and r.ref_state_id is not null;
  -- Insert remote refs
  if new.remote_tf_state_refs is not null then
    for ds_key, ds_value in
      select key, value from jsonb_each(new.remote_tf_state_refs)
    loop
      select (h.data->>'remote_state')::uuid into remote_state_id
      from hcl h
      where h.state_id = new.state_id
        and h.address = ds_key
        and h.data->>'remote_state' is not null;
      if remote_state_id is not null then
        for ref_item in
          select jsonb_array_elements_text(ds_value)
        loop
          insert into hcl_refs (state_id, id, ref, ref_state_id)
          values (new.state_id, new.id, ref_item, remote_state_id)
          on conflict do nothing;
        end loop;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger hcl_refs_sync on hcl;

create trigger hcl_refs_sync
after insert or update of refs, remote_tf_state_refs
on hcl
for each row
execute function sync_hcl_refs();

