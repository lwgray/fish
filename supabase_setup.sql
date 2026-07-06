-- ============================================================
--  Panfish Log — Supabase setup (complete, from-scratch)
--  Paste into  Supabase → SQL Editor → New query → Run.
--  Safe to run more than once. Contains NO drop statements, so it
--  will NOT trigger the "destructive operation" warning.
-- ============================================================

-- ---------- TABLES ----------
create table if not exists public.trips (
  id            text primary key,
  user_id       uuid not null default auth.uid(),
  date          date,
  water_body    text,
  county        text,
  launch_lat    double precision,
  launch_lon    double precision,
  start_time    text,
  end_time      text,
  total_hours   numeric,
  anglers       text,
  watercraft    text,
  target_species text,
  air_temp_f    numeric,
  wind_mph      numeric,
  wind_dir      text,
  sky           text,
  pressure_inhg numeric,
  pressure_trend text,
  moon_phase    text,
  water_temp_f  numeric,
  water_clarity text,
  water_level   text,
  notes         text,
  created_at    timestamptz default now()
);

create table if not exists public.spots (
  id            text primary key,
  user_id       uuid not null default auth.uid(),
  trip_id       text,
  spot_name     text,
  lat           double precision,
  lon           double precision,
  depth_ft      numeric,
  structure     text,
  bottom        text,
  water_temp_f  numeric,
  time_start    text,
  time_end      text,
  minutes_fished numeric,
  rods          numeric,
  num_catches   numeric,
  cpue_per_hr   numeric,
  primary_technique text,
  notes         text,
  created_at    timestamptz default now()
);

create table if not exists public.catches (
  id             text primary key,
  user_id        uuid not null default auth.uid(),
  trip_id        text,
  effort_id      text,
  time           text,
  species        text,
  length_in      numeric,
  length_type    text,
  weight_g       numeric,
  weight_oz      numeric,
  depth_caught_ft numeric,
  lure_bait      text,
  lure_color     text,
  lure_size      text,
  technique      text,
  retrieve_speed text,
  kept_released  text,
  sex            text,
  condition      text,
  photo_file     text,
  video_file     text,
  missed         boolean default false,
  angler         text,
  notes          text,
  lat            double precision,
  lon            double precision,
  created_at     timestamptz default now()
);

-- Columns that were added over time (for databases created before they existed).
alter table public.catches add column if not exists video_file text;
alter table public.catches add column if not exists missed boolean default false;

-- ---------- ROW LEVEL SECURITY ----------
-- Everyone signed in can READ all rows (shared family dataset),
-- but can only INSERT/UPDATE rows tagged with their own user_id.
alter table public.trips   enable row level security;
alter table public.spots   enable row level security;
alter table public.catches enable row level security;

do $$
declare t text;
begin
  foreach t in array array['trips','spots','catches'] loop
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='read all '||t) then
      execute format('create policy "read all %1$s" on public.%1$s for select to authenticated using (true);', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='insert own '||t) then
      execute format('create policy "insert own %1$s" on public.%1$s for insert to authenticated with check (user_id = auth.uid());', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='update own '||t) then
      execute format('create policy "update own %1$s" on public.%1$s for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());', t);
    end if;
  end loop;
end $$;

-- ---------- STORAGE BUCKETS (photos + videos) ----------
insert into storage.buckets (id, name, public) values ('photos','photos', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('videos','videos', false) on conflict (id) do nothing;

do $$
declare b text;
begin
  foreach b in array array['photos','videos'] loop
    if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname=b||' read') then
      execute format('create policy "%1$s read" on storage.objects for select to authenticated using (bucket_id = %1$L);', b);
    end if;
    if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname=b||' insert') then
      execute format('create policy "%1$s insert" on storage.objects for insert to authenticated with check (bucket_id = %1$L);', b);
    end if;
    if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname=b||' update') then
      execute format('create policy "%1$s update" on storage.objects for update to authenticated using (bucket_id = %1$L);', b);
    end if;
  end loop;
end $$;

-- Done. Tables: trips, spots, catches (incl. video_file + missed).
--       Buckets: photos, videos, each with read/insert/update policies.
--       No DROP statements, so no destructive-operation warning.
