-- Supabase migration script: tables, RLS, RPC and triggers for ticketing rules.

-- 1) Branches
create table if not exists branches (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null
);

-- 2) Profiles (links auth.users)
create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null, -- admin|manager|staff|master
  branch_id uuid references branches(id)
);

-- 3) Items
create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references branches(id),
  name text not null,
  price numeric not null,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4) Item price logs
create table if not exists item_price_logs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references items(id),
  branch_id uuid references branches(id),
  old_price numeric,
  new_price numeric,
  changed_by uuid references auth.users(id),
  changed_at timestamptz default now()
);

-- 5) Tickets: added printed_once and printed_at per RULE-2
create table if not exists tickets (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references branches(id),
  branch_code text,
  ticket_no text unique,
  created_at timestamptz default now(),
  staff_user_id uuid references auth.users(id),
  payment_mode text,
  subtotal numeric,
  discount_type text,
  discount_value numeric,
  discount_amount numeric,
  final_amount numeric,
  gst_rate numeric default 18,
  gst_included boolean default true,
  agent_id text,
  commission_percent numeric,
  commission_amount numeric,
  commission_paid boolean default false,
  commission_paid_at timestamptz,
  commission_paid_by uuid references auth.users(id),
  printed_once boolean default false,
  printed_at timestamptz
);

-- 6) Ticket items
create table if not exists ticket_items (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid references tickets(id) on delete cascade,
  item_id uuid references items(id),
  item_name_snapshot text,
  unit_price_snapshot numeric,
  qty int,
  line_total numeric
);

-- Enable RLS where appropriate
alter table items enable row level security;
alter table tickets enable row level security;
alter table ticket_items enable row level security;
alter table item_price_logs enable row level security;
alter table profiles enable row level security;

-- POLICY CREATION (type-safe adaptive block)
do $$
declare
  uid_col text;
  uid_col_type text;
  branch_col text;
  branch_col_type text;
  uid_cmp text;
  branch_match_expr text;
begin
  -- pick user-id column (preference order)
  select column_name, udt_name into uid_col, uid_col_type
  from information_schema.columns
  where table_schema = current_schema()
    and table_name = 'profiles'
    and column_name in ('user_id','wp_user_id','id')
  order by case when column_name = 'user_id' then 1 when column_name = 'wp_user_id' then 2 when column_name = 'id' then 3 else 4 end
  limit 1;

  if uid_col is null then
    uid_col := 'user_id';
    uid_col_type := null;
  end if;

  -- pick branch column (preference order)
  select column_name, udt_name into branch_col, branch_col_type
  from information_schema.columns
  where table_schema = current_schema()
    and table_name = 'profiles'
    and column_name in ('branch','branch_id')
  order by case when column_name = 'branch' then 1 when column_name = 'branch_id' then 2 else 3 end
  limit 1;

  if branch_col is null then
    branch_col := 'branch_id';
    branch_col_type := null;
  end if;

  -- build uid comparison expression: if profile uid column is uuid, cast auth.uid() to uuid
  if uid_col_type = 'uuid' then
    uid_cmp := format('p.%I = auth.uid()::uuid', uid_col);
  else
    uid_cmp := format('p.%I = auth.uid()', uid_col);
  end if;

  -- build branch match expression comparing as text to avoid text=uuid errors
  branch_match_expr := format('(p.%1$I::text = tickets.branch_code OR p.%1$I::text = tickets.branch_id::text)', branch_col);

  -- Drop policies if they exist (safe)
  execute 'drop policy if exists profiles_self on profiles';
  execute 'drop policy if exists items_select on items';
  execute 'drop policy if exists items_insert on items';
  execute 'drop policy if exists items_update on items';
  execute 'drop policy if exists tickets_select on tickets';
  execute 'drop policy if exists tickets_insert on tickets';
  execute 'drop policy if exists tickets_update_master_only on tickets';
  execute 'drop policy if exists tickets_delete_master_only on tickets';
  execute 'drop policy if exists ticket_items_select on ticket_items';
  execute 'drop policy if exists ticket_items_insert on ticket_items';
  execute 'drop policy if exists logs_select on item_price_logs';

  -- profiles: users can only manage/select their own profile rows
  execute format($sql$
    create policy profiles_self on profiles
      for all using (%1$s) with check (%1$s)
  $sql$, uid_cmp);

  -- Items: select (allow master/admin or branch members)
  execute format($sql$
    create policy items_select on items
      for select using (
        exists (
          select 1 from profiles p where %1$s and (p.role = 'master' or p.role = 'admin' or p.%2$I::text = items.branch_id::text)
        )
      )
  $sql$, uid_cmp, branch_col);

  -- Items: insert (master/admin/manager)
  execute format($sql$
    create policy items_insert on items
      for insert with check (
        exists (
          select 1 from profiles p where %1$s and (p.role = 'master' or p.role = 'admin' or p.role = 'manager')
        )
      )
  $sql$, uid_cmp);

  -- Items: update (master/admin or manager for branch)
  execute format($sql$
    create policy items_update on items
      for update using (
        exists (
          select 1 from profiles p where %1$s and (p.role = 'master' or p.role = 'admin' or (p.role = 'manager' and p.%2$I::text = items.branch_id::text))
        )
      ) with check (
        exists (
          select 1 from profiles p where %1$s and (p.role = 'master' or p.role = 'admin' or (p.role = 'manager' and p.%2$I::text = items.branch_id::text))
        )
      )
  $sql$, uid_cmp, branch_col);

  -- Tickets: SELECT (master/admin all; manager/staff only their branch)
  execute format($sql$
    create policy tickets_select on tickets
      for select using (
        exists (
          select 1 from profiles p where %1$s and (
            p.role = 'master' or p.role = 'admin' or ((p.role = 'manager' or p.role = 'staff') and %2$s)
          )
        )
      )
  $sql$, uid_cmp, branch_match_expr);

  -- Tickets: INSERT
  -- master/admin any; manager/staff only if branch matches; also validate branch_id matches branches.id for branch_code
  execute format($sql$
    create policy tickets_insert on tickets
      for insert with check (
        -- branch must correspond to branches table
        (tickets.branch_code is not null and tickets.branch_id is not null and exists (select 1 from branches b where b.code = tickets.branch_code and b.id = tickets.branch_id))
        and
        exists (
          select 1 from profiles p where %1$s and (
            p.role in ('master','admin')
            or (p.role = 'manager' and p.%2$I::text = tickets.branch_code)
            or (p.role = 'staff' and p.%2$I::text = tickets.branch_code and tickets.staff_user_id = auth.uid()::uuid)
          )
        )
      )
  $sql$, uid_cmp, branch_col);

  -- Tickets: UPDATE only master
  execute format($sql$
    create policy tickets_update_master_only on tickets
      for update using (
        exists (select 1 from profiles p where %1$s and p.role = 'master')
      ) with check (
        exists (select 1 from profiles p where %1$s and p.role = 'master')
      )
  $sql$, uid_cmp);

  -- Tickets: DELETE only master
  execute format($sql$
    create policy tickets_delete_master_only on tickets
      for delete using (
        exists (select 1 from profiles p where %1$s and p.role = 'master')
      )
  $sql$, uid_cmp);

  -- Ticket items: SELECT (inherit ticket visibility)
  execute format($sql$
    create policy ticket_items_select on ticket_items
      for select using (
        exists (
          select 1 from tickets t join profiles p on %1$s
          where t.id = ticket_items.ticket_id and (p.role = 'master' or p.role = 'admin' or p.%2$I::text = t.branch_code)
        )
      )
  $sql$, uid_cmp, branch_col);

  -- Ticket items: INSERT
  -- Ensure parent ticket exists, user allowed on that ticket, item belongs to same branch, and qty/line_total checks
  execute format($sql$
    create policy ticket_items_insert on ticket_items
      for insert with check (
        exists (select 1 from tickets t where t.id = ticket_items.ticket_id)
        and exists (
          select 1 from profiles p where %1$s and (
            p.role in ('master','admin')
            or ((p.role = 'manager' or p.role = 'staff') and p.%2$I::text = (select t2.branch_code from tickets t2 where t2.id = ticket_items.ticket_id))
          )
        )
        and exists (
          select 1 from items i where i.id = ticket_items.item_id and i.branch_id = (select t3.branch_id from tickets t3 where t3.id = ticket_items.ticket_id)
        )
        and ticket_items.qty > 0
        and ticket_items.line_total >= 0
      )
  $sql$, uid_cmp, branch_col);

  -- item_price_logs select policy (master/admin or branch match)
  execute format($sql$
    create policy logs_select on item_price_logs
      for select using (
        exists (
          select 1 from profiles p where %1$s and (p.role = 'master' or p.role = 'admin' or p.%2$I::text = item_price_logs.branch_id::text)
        )
      )
  $sql$, uid_cmp, branch_col);

end
$$;

-- RULE-2: RPC to mark ticket printed: will raise error if already printed.
create or replace function public.mark_ticket_printed(p_ticket_id uuid)
returns void language plpgsql security definer as $$
begin
  -- check existence
  if not exists (select 1 from tickets where id = p_ticket_id) then
    raise exception 'ticket not found';
  end if;

  -- if already printed, error
  if (select printed_once from tickets where id = p_ticket_id) = true then
    raise exception 'ticket already printed';
  end if;

  update tickets set printed_once = true, printed_at = now() where id = p_ticket_id;
end;
$$;

-- RULE-2: Trigger to prevent un-printing (prevent printed_once true -> false)
create or replace function public.prevent_unprint_trigger()
returns trigger language plpgsql as $$
begin
  -- If printed_once was true and new value attempts to set false, block
  if (OLD.printed_once = true and NEW.printed_once = false) then
    raise exception 'cannot set printed_once from true to false';
  end if;
  return NEW;
end;
$$;

-- Attach trigger
drop trigger if exists prevent_unprint on tickets;
create trigger prevent_unprint
  before update on tickets
  for each row execute function public.prevent_unprint_trigger();

-- Notes:
-- - mark_ticket_printed is SECURITY DEFINER so it can update tickets even if RLS would normally block; the trigger prevents un-printing.
-- - This migration adapts to profiles column names to avoid "column does not exist" errors.
