-- ============================================================
--  Panfish Log — Supabase setup
--  Paste this whole file into  Supabase → SQL Editor → New query → Run.
--  Safe to run more than once.
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
  angler         text,
  notes          text,
  lat            double precision,
  lon            double precision,
  created_at     timestamptz default now()
);

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
    execute format('drop policy if exists "read all %1$s"  on public.%1$s;', t);
    execute format('drop policy if exists "insert own %1$s" on public.%1$s;', t);
    execute format('drop policy if exists "update own %1$s" on public.%1$s;', t);
    execute format('create policy "read all %1$s"  on public.%1$s for select to authenticated using (true);', t);
    execute format('create policy "insert own %1$s" on public.%1$s for insert to authenticated with check (user_id = auth.uid());', t);
    execute format('create policy "update own %1$s" on public.%1$s for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());', t);
  end loop;
end $$;

-- ---------- PHOTO STORAGE ----------
insert into storage.buckets (id, name, public)
values ('photos','photos', false)
on conflict (id) do nothing;

drop policy if exists "photos read"   on storage.objects;
drop policy if exists "photos insert" on storage.objects;
drop policy if exists "photos update" on storage.objects;
create policy "photos read"   on storage.objects for select to authenticated using (bucket_id = 'photos');
create policy "photos insert" on storage.objects for insert to authenticated with check (bucket_id = 'photos');
create policy "photos update" on storage.objects for update to authenticated using (bucket_id = 'photos');

-- ---------- VIDEO CLIPS (FishClip "got a bite") ----------
alter table public.catches add column if not exists video_file text;

insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do nothing;

drop policy if exists "videos read"   on storage.objects;
drop policy if exists "videos insert" on storage.objects;
drop policy if exists "videos update" on storage.objects;
create policy "videos read"   on storage.objects for select to authenticated using (bucket_id = 'videos');
create policy "videos insert" on storage.objects for insert to authenticated with check (bucket_id = 'videos');
create policy "videos update" on storage.objects for update to authenticated using (bucket_id = 'videos');

-- Done. Tables: trips, spots, catches.  Buckets: photos, videos.
