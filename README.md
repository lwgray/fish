# Panfish Log

A single-file, offline-first mobile web app for logging panfish, crappie, and bass
trips in Idaho — built for clean, prediction-ready data collection.

## What it does

- One-tap catch logging (species, length, weight, lure, photo) with automatic
  time + GPS stamp.
- Auto-captures weather, barometric pressure + trend, wind, and moon phase at trip
  start via Open-Meteo (no API key needed).
- Tracks **effort per spot** — including zero-catch spots — so catch-per-hour (CPUE)
  can be computed later.
- Works fully offline on the water; syncs to Supabase in the background using
  anonymous auth (no sign-in screen).

## Run it

It's one file: `PanfishLog.html`. It must be served over **HTTPS**, because GPS and
the camera require a secure context (opening the raw file won't grant them).

- Quickest: drag `PanfishLog.html` onto https://app.netlify.com/drop, open the
  resulting link on your phone, then **Add to Home Screen**.
- Or any static host: GitHub Pages, Cloudflare Pages, Vercel.

## Backend (Supabase)

1. Create a free Supabase project.
2. Run [`supabase_setup.sql`](./supabase_setup.sql) in the SQL Editor. It creates the
   `trips`, `spots`, and `catches` tables, a `photos` storage bucket, and row-level
   security policies.
3. Enable **Anonymous sign-ins** (Authentication → Sign In / Providers).
4. The project URL and anon public key are embedded in `PanfishLog.html` (the `EMBED`
   constant near the bottom of the script). The anon key is **public by design** —
   row-level security is what protects the data.

## Data model

| Table     | Grain                         | Notes                                        |
|-----------|-------------------------------|----------------------------------------------|
| `trips`   | one row per outing            | location, weather, pressure, moon            |
| `spots`   | one row per spot within a trip| effort (minutes), depth, structure, CPUE     |
| `catches` | one row per fish              | the core observations + photo reference      |

## Roadmap

- Auto-measure length from the bump-board photo.
- Sync a Bluetooth fish finder for depth + water temperature.
- Catch-rate prediction (CPUE vs. barometric trend, lure-by-species, depth-vs-size).
- Public Idaho panfishing site.

## License

TBD
