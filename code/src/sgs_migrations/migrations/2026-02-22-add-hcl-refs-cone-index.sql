create index hcl_refs_state_id_id_ref_state_idx
on hcl_refs (state_id, id)
where ref_state_id is not null
