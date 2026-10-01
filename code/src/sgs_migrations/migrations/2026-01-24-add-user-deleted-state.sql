-- Add 'deleted' state for soft delete
insert into user_states(id) values ('deleted')
on conflict (id) do nothing;

-- Index for filtering active users
create index if not exists users_state_idx on users (state)
    where state = 'active';

comment on table user_states is 'Valid states for users: active, deleted';
