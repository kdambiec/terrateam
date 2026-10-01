-- Phase 1 of the security findings feature.
--
-- Schema for: scan envelope, per-scan findings, plus source-location
-- columns on `hcl` used for L1 line-translation (reified HCL
-- coordinates -> the user's original file:line range).
--
-- This migration ships only the tables that Sgs_security_job actually
-- writes today.  The follow-on Phase 2 tables (controls, control_results,
-- suppressions, notification_rules) ship in a separate migration so that
-- this initial schema stays minimal.
--
-- See code/security_final_plan.md for the design.  Constraints accept
-- plan/preview-time values (kind='planned', triggered_by='preview') from
-- day one so plan/preview-time scanning lands additively.

-- =========================================================================
-- security_scans: scan envelope, one row per scanner invocation
-- =========================================================================

create table security_scans (
  id uuid primary key default (gen_random_uuid()),
  state_id uuid not null,
  tenant_id uuid not null,
  tx_id uuid,
  scanned_at timestamp with time zone not null default (now()),
  kind text not null check (kind in ('current', 'planned')),
  triggered_by text not null check (triggered_by in
    ('state_import', 'tx_apply', 'actuator_commit', 'preview', 'scheduled', 'manual')),
  scanner text not null,
  scanner_version text,
  status text not null check (status in ('running', 'completed', 'failed')),
  finding_count integer not null default 0,
  severity_breakdown jsonb not null default '{}'::jsonb,
  error_message text,
  foreign key (state_id) references states(id),
  foreign key (tenant_id) references tenants(id),
  foreign key (tx_id) references transactions(id),
  -- planned scans must reference a tx; current scans must not.
  check ((kind = 'current' and tx_id is null)
      or (kind = 'planned' and tx_id is not null))
);

create index security_scans_state_kind_scanned_at_idx
  on security_scans (state_id, kind, scanned_at desc);

-- Partial: most rows are kind='current' with NULL tx_id; indexing only
-- tx-linked rows keeps it small.
create index security_scans_tx_id_idx
  on security_scans (tx_id) where tx_id is not null;


-- =========================================================================
-- security_scan_findings: per-finding rows produced by a scan
-- =========================================================================
--
-- Enrichment columns (blast_radius_*, is_internet_reachable*,
-- cross_state_refs) are populated in a second pass after the raw insert
-- and are idempotent to recompute when the graph changes.
--
-- fingerprint = sha1(check_id || ':' || resource_fq_address); invariant
-- across scan modes so the lifecycle FKs (first_seen_scan_id /
-- resolved_scan_id) track correctly across current<->planned scans.

create table security_scan_findings (
  scan_id uuid not null,
  fingerprint text not null,
  check_id text not null,
  resource_fq_address text not null,
  state_id uuid not null,

  -- L1 translation: a snapshot of the finding's source location, filled at
  -- scan time by joining `hcl` on (state_id, fq_address). Snapshotted onto
  -- the finding (rather than derived at read time) so a later HCL edit does
  -- not retroactively move a historical finding's reported location.
  source_file text,
  source_start_line integer,
  source_end_line integer,

  -- Severity: stored normalized (lowercased), never null -- "unknown" stands
  -- in for a scanner that reported no severity. severity_reason is the optional
  -- provenance / adjustment note, if any
  severity_base text not null default 'unknown',
  severity_effective text not null default 'unknown',
  severity_reason text,

  -- Enrichment (populated by enrichment pass after raw insert).
  -- Size of the blast, in terms of resources. We only keep the count, we don't store them, as it may be very large.
  blast_radius_resource_count integer,
  -- Size of the blast, in number of modules. We store them, as it's bounded by a repo's number of files.
  blast_radius_modules text[],
  is_internet_reachable boolean,
  internet_reachability_evidence jsonb,
  cross_state_refs uuid[],

  -- Lifecycle (Josh R8/R9).
  first_seen_scan_id uuid,
  resolved_scan_id uuid,

  primary key (scan_id, check_id, resource_fq_address),
  foreign key (scan_id) references security_scans(id),
  foreign key (state_id) references states(id),
  foreign key (first_seen_scan_id) references security_scans(id),
  foreign key (resolved_scan_id) references security_scans(id)
);

create index security_scan_findings_fingerprint_idx
  on security_scan_findings (state_id, fingerprint);

create index security_scan_findings_scan_check_id_idx
  on security_scan_findings (scan_id, check_id);

create index security_scan_findings_resource_idx
  on security_scan_findings (state_id, resource_fq_address);

create index security_scan_findings_check_id_idx
  on security_scan_findings (check_id);

create index security_scan_findings_effective_severity_idx
  on security_scan_findings (state_id, severity_effective);


-- =========================================================================
-- L1: source-location columns on the existing `hcl` table. Source location
-- is a property of where an HCL block is *defined*, so it belongs on `hcl`
-- (source-level). Populated by HCL ingestion so that findings on reified HCL
-- can be reported against the user's original file:line range.
-- =========================================================================

alter table hcl
  add column source_file text,
  add column source_start_line integer,
  add column source_end_line integer;
