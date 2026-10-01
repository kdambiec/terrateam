ALTER TABLE instances
  DROP CONSTRAINT instances_state_id_resource_address_mode_fkey;

UPDATE instances
SET resource_address = 'data.' || resource_address,
    address = 'data.' || address
WHERE mode = 'data'
  AND resource_address NOT LIKE 'data.%';

UPDATE resources
SET address = 'data.' || address
WHERE mode = 'data'
  AND address NOT LIKE 'data.%';

ALTER TABLE instances
  ADD CONSTRAINT instances_state_id_resource_address_mode_fkey
    FOREIGN KEY (state_id, resource_address, mode)
    REFERENCES resources(state_id, address, mode);
