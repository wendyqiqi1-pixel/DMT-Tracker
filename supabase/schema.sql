-- DMT Daily Tracker: database schema, access rules and memo storage.
-- Run once in Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run: objects are created only if missing and policies are replaced.

-- ============ Tables ============
create table if not exists public.team_members (
  key        text primary key,                 -- short id used in reports, e.g. "nik"
  name       text not null,                    -- name as it appears in the daily report
  email      text unique,                      -- Outlook / Microsoft 365 sign-in email (lower case)
  role       text not null default 'staff' check (role in ('staff','supervisor','manager')),
  sort       int  not null default 0,          -- report order
  active     boolean not null default true,    -- false = removed (keeps history, blocks sign-in)
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  id         int primary key default 1 check (id = 1),
  topics     jsonb not null default '[]'::jsonb,
  channels   jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.entries (          -- one row per staff per day
  id         text primary key,                      -- "<yyyy-mm-dd>__<staff key>"
  date       date not null,
  staff      text not null references public.team_members(key) on update cascade,
  channels   jsonb not null default '{}'::jsonb,     -- {"CALL": 12, "EMAIL": 20, ...}
  topics     jsonb not null default '{}'::jsonb,     -- {"DEALERSHIP": 8, ...}
  notes      jsonb not null default '[]'::jsonb,     -- issue notes [{id, topic, text, at, by}]
  total      int  not null default 0,
  updated_by text,
  updated_at timestamptz not null default now()
);
create index if not exists entries_date_idx on public.entries(date);
create index if not exists entries_staff_idx on public.entries(staff);

create table if not exists public.crm_logs (         -- one row per dealer contact handled
  id          uuid primary key default gen_random_uuid(),
  date        date not null,                         -- working day the contact belongs to
  logged_at   timestamptz not null default now(),
  staff       text not null references public.team_members(key) on update cascade,
  channel     text not null,                         -- CALL / WHATSAPP / FACEBOOK / EMAIL / WALK-IN
  topic       text not null,
  contact     text,                                  -- phone number, WhatsApp number, email or Facebook name
  dealer_id   text,
  description text not null,
  status      text not null default 'resolved' check (status in ('resolved','follow-up','forwarded')),
  created_by  text,
  updated_by  text,
  updated_at  timestamptz not null default now()
);
create index if not exists crm_logs_date_staff_idx on public.crm_logs(date, staff);
create index if not exists crm_logs_dealer_idx on public.crm_logs(dealer_id);

create table if not exists public.summaries (        -- team report ISSUE notes per day
  date       date primary key,
  notes      jsonb not null default '[]'::jsonb,
  imported   jsonb,                                  -- optional team-level breakdown for back-filled days
  updated_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.campaigns (
  id         text primary key,
  data       jsonb not null,                         -- name, code, audience, start, end, mechanics, memos, ...
  updated_by text,
  updated_at timestamptz not null default now()
);

-- ============ Who is signed in ============
-- Matches the Microsoft sign-in email to an active team member.
create or replace function public.my_member_key() returns text
language sql stable security definer set search_path = public as $$
  select key from public.team_members
  where active and email is not null and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.team_members
  where active and email is not null and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1
$$;

revoke all on function public.my_member_key() from public;
revoke all on function public.my_role() from public;
grant execute on function public.my_member_key() to authenticated;
grant execute on function public.my_role() to authenticated;

-- ============ Row-level security ============
alter table public.team_members enable row level security;
alter table public.settings     enable row level security;
alter table public.entries      enable row level security;
alter table public.summaries    enable row level security;
alter table public.campaigns    enable row level security;

-- Team list: every team member can read it; only managers change it.
drop policy if exists tm_read  on public.team_members;
drop policy if exists tm_write on public.team_members;
create policy tm_read  on public.team_members for select to authenticated using (public.my_role() is not null);
create policy tm_write on public.team_members for all    to authenticated using (public.my_role() = 'manager') with check (public.my_role() = 'manager');

-- Topics and channels: read by all members, changed by managers.
drop policy if exists st_read  on public.settings;
drop policy if exists st_write on public.settings;
create policy st_read  on public.settings for select to authenticated using (public.my_role() is not null);
create policy st_write on public.settings for all    to authenticated using (public.my_role() = 'manager') with check (public.my_role() = 'manager');

-- Daily cases: all members read (team totals); support staff write only their own rows;
-- supervisors and managers can correct anyone's.
drop policy if exists en_read   on public.entries;
drop policy if exists en_insert on public.entries;
drop policy if exists en_update on public.entries;
drop policy if exists en_delete on public.entries;
create policy en_read   on public.entries for select to authenticated using (public.my_role() is not null);
create policy en_insert on public.entries for insert to authenticated
  with check (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()));
create policy en_update on public.entries for update to authenticated
  using      (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()))
  with check (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()));
create policy en_delete on public.entries for delete to authenticated using (public.my_role() in ('supervisor','manager'));

-- CRM log: all members read (dealer history); support staff add, edit and delete only their own;
-- supervisors and managers can correct anyone's.
alter table public.crm_logs enable row level security;
drop policy if exists crm_read   on public.crm_logs;
drop policy if exists crm_insert on public.crm_logs;
drop policy if exists crm_update on public.crm_logs;
drop policy if exists crm_delete on public.crm_logs;
create policy crm_read   on public.crm_logs for select to authenticated using (public.my_role() is not null);
create policy crm_insert on public.crm_logs for insert to authenticated
  with check (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()));
create policy crm_update on public.crm_logs for update to authenticated
  using      (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()))
  with check (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()));
create policy crm_delete on public.crm_logs for delete to authenticated
  using (public.my_role() in ('supervisor','manager') or (public.my_role() = 'staff' and staff = public.my_member_key()));

-- Daily totals follow the CRM log automatically: every insert, edit or delete recounts that
-- staff member's day (channels, topics, total) in public.entries. Issue notes are left untouched.
create or replace function public.recount_entry(p_date date, p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare ch jsonb; tp jsonb; tot int;
begin
  select coalesce(jsonb_object_agg(channel, n), '{}'::jsonb) into ch
    from (select channel, count(*)::int n from public.crm_logs where date = p_date and staff = p_staff group by channel) s;
  select coalesce(jsonb_object_agg(topic, n), '{}'::jsonb) into tp
    from (select topic, count(*)::int n from public.crm_logs where date = p_date and staff = p_staff and coalesce(topic,'') <> '' group by topic) s;
  select count(*)::int into tot from public.crm_logs where date = p_date and staff = p_staff;
  insert into public.entries (id, date, staff, channels, topics, total, updated_by, updated_at)
  values (p_date::text || '__' || p_staff, p_date, p_staff, ch, tp, tot, 'crm-log', now())
  on conflict (id) do update
    set channels = excluded.channels, topics = excluded.topics, total = excluded.total,
        updated_by = excluded.updated_by, updated_at = now();
end $$;
revoke all on function public.recount_entry(date, text) from public;

create or replace function public.crm_logs_recount() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('INSERT','UPDATE') then perform public.recount_entry(new.date, new.staff); end if;
  if tg_op in ('UPDATE','DELETE') and (tg_op = 'DELETE' or old.date <> new.date or old.staff <> new.staff) then
    perform public.recount_entry(old.date, old.staff);
  end if;
  return null;
end $$;

drop trigger if exists crm_logs_recount on public.crm_logs;
create trigger crm_logs_recount after insert or update or delete on public.crm_logs
  for each row execute function public.crm_logs_recount();

-- Team report notes: read by all members, written by supervisors and managers.
drop policy if exists su_read  on public.summaries;
drop policy if exists su_write on public.summaries;
create policy su_read  on public.summaries for select to authenticated using (public.my_role() is not null);
create policy su_write on public.summaries for all    to authenticated using (public.my_role() in ('supervisor','manager')) with check (public.my_role() in ('supervisor','manager'));

-- Campaigns: read by all members, managed by supervisors and managers.
drop policy if exists ca_read  on public.campaigns;
drop policy if exists ca_write on public.campaigns;
create policy ca_read  on public.campaigns for select to authenticated using (public.my_role() is not null);
create policy ca_write on public.campaigns for all    to authenticated using (public.my_role() in ('supervisor','manager')) with check (public.my_role() in ('supervisor','manager'));

-- ============ Memo files (private storage bucket) ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('memos', 'memos', false, 20971520, array['application/pdf','image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;

drop policy if exists memos_read   on storage.objects;
drop policy if exists memos_insert on storage.objects;
drop policy if exists memos_delete on storage.objects;
create policy memos_read   on storage.objects for select to authenticated using (bucket_id = 'memos' and public.my_role() is not null);
create policy memos_insert on storage.objects for insert to authenticated with check (bucket_id = 'memos' and public.my_role() in ('supervisor','manager'));
create policy memos_delete on storage.objects for delete to authenticated using (bucket_id = 'memos' and public.my_role() in ('supervisor','manager'));

-- ============ Live updates ============
do $$
declare t text;
begin
  foreach t in array array['team_members','settings','entries','summaries','campaigns','crm_logs'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ============ Default topics and channels ============
insert into public.settings (id, topics, channels) values (1,
  '["DEALERSHIP","INCENTIVE","MNP ISSUE","INFO","USER ISSUE (forward to CS team)","OWNERSHIP","REGISTER ISSUE","ERECHARGE","KPI","VIP NUMBER","CP58","E-INVOICE","BLACK","AFFILIATE","HIERARCHY","DREG","FRAUD","LOGIN/ ONESYS","SRP","Esim","ONEXAPP"]'::jsonb,
  '["CALL","WHATSAPP","FACEBOOK","EMAIL","WALK-IN"]'::jsonb)
on conflict (id) do nothing;

-- Projects created before the CRM log: switch the original 4 channels to the CRM log's 5.
update public.settings set channels = '["CALL","WHATSAPP","FACEBOOK","EMAIL","WALK-IN"]'::jsonb
where id = 1 and channels = '["CALL","EMAIL","WHATSAPP","WALK-IN"]'::jsonb;

-- ============ First manager (edit, then run this line on its own) ============
-- Nobody can sign in until at least one manager exists. Replace the name and email,
-- remove the leading "--", and run it. Add everyone else from the app's Team & topics tab.
-- insert into public.team_members (key, name, email, role, sort) values ('your-name', 'Your Name', 'you@yourcompany.com', 'manager', 0);
