-- 1) Show branch UUID for code 'JPR'
select id as branch_id
from branches
where code = 'JPR';

-- 2) Insert 3 sample active items for branch 'JPR'
-- 3) Ensure items.branch_id is UUID type (attempt safe alter if needed)
begin;

-- ensure branch exists; fail early if not
do $$
declare
  b_id uuid;
begin
  select id into b_id from branches where code = 'JPR' limit 1;
  if b_id is null then
    raise exception 'Branch with code JPR not found - aborting.';
  end if;
end
$$;

-- ensure items.branch_id column exists and is uuid; try to alter if not
do $$
declare
  coltype text;
begin
  select udt_name into coltype
  from information_schema.columns
  where table_schema = current_schema()
    and table_name = 'items'
    and column_name = 'branch_id';

  if coltype is null then
    raise exception 'Column items.branch_id does not exist in schema % - please create it first.', current_schema();
  elsif coltype <> 'uuid' then
    -- Attempt to alter type using safe cast; will fail if values cannot be cast
    begin
      alter table items alter column branch_id type uuid using (branch_id::uuid);
      perform 1; -- noop to indicate success
    exception when others then
      raise exception 'Failed to alter items.branch_id to uuid: %', sqlerrm;
    end;
  end if;
end
$$;

-- Insert sample items using subquery to fetch branch id dynamically
with b as (
  select id
  from branches
  where code = 'JPR'
  limit 1
), sample(name, price, active) as (
  values
    ('Tyre A', 199.00, true),
    ('Oil Change', 299.00, true),
    ('Washer Fluid', 49.00, true)
)
insert into items (branch_id, name, price, active, created_at)
select b.id, s.name, s.price, s.active, now()
from b cross join sample s
returning id, name, branch_id;

commit;
