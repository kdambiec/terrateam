alter table instances
  drop constraint instances_pkey,
  drop constraint instances_state_id_resource_address_fkey;

alter table resources
  drop constraint resources_pkey;

alter table resources
  add primary key (state_id, address, mode);

alter table instances
  add column mode text;

update instances as i set
  mode = r.mode
from resources as r
where i.resource_address = r.address;

alter table instances
  add primary key (state_id, address, mode),
  add constraint instances_state_id_resource_address_mode_fkey
    foreign key (state_id, resource_address, mode)
    references resources(state_id, address, mode);

