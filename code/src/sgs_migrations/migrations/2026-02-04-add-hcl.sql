insert into transaction_log_actions (id) values ('hcl_set'), ('hcl_delete');

insert into transaction_log_object_types (id) values ('hcl');

create table hcl (
  address text not null,
  created_at timestamp with time zone not null default (now()),
  data jsonb not null,
  id text not null,
  module_path text,
  refs text[] not null,
  state_id uuid not null,
  updated_at timestamp with time zone not null default (now()),
  primary key (state_id, id),
  foreign key (state_id) references states(id)
);

create index hcl_state_address_idx on hcl (state_id, module_path, address);

create table hcl_refs (
  state_id uuid not null,
  id text not null,
  ref text not null,
  primary key (state_id, id, ref),
  foreign key (state_id, id) references hcl (state_id, id)
    on delete cascade
);

create index hcl_refs_state_ref_idx on hcl_refs (state_id, ref);

create or replace function sync_hcl_refs()
returns trigger
language plpgsql
as $$
begin
  -- Delete refs that were removed
  delete from hcl_refs r
  where r.state_id = new.state_id
    and r.id = new.id
    and not (r.ref = any (new.refs));
  -- Insert new refs that do not yet exist
  insert into hcl_refs (state_id, id, ref)
  select new.state_id, new.id, ref
  from unnest(new.refs) as ref
  on conflict do nothing;
  return new;
end;
$$;

create trigger hcl_refs_sync
after insert or update of refs
on hcl
for each row
execute function sync_hcl_refs();
