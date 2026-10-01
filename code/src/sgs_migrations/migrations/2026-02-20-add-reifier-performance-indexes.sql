create index hcl_state_id_address_idx on hcl (state_id, address);

create index hcl_refs_ref_state_id_ref_idx on hcl_refs (ref_state_id, ref)
    where ref_state_id is not null;
