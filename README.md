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

## Run it (Cloudflare Pages)

It's one static file: `index.html`. It must be served over **HTTPS**, because GPS and
the camera require a secure context (opening the raw file won't grant them).
Cloudflare Pages provides HTTPS automatically.

### Option A — auto-deploy from GitHub (recommended)

1. Push this repo to GitHub.
2. Cloudflare dashboard → **Workers & Pages → Create → Pages → Connect to Git**, and
   select this repository.
3. Framework preset: **None**. Build command: *(leave empty)*. Build output
   directory: **`/`**.
4. **Save and Deploy.** Every `git push` to `main` then redeploys automatically.

### Option B — one-off from your machine (Wrangler CLI)

```bash
cd ~/dev/fish
npx wrangler pages deploy . --project-name=fish
```

Either way the app goes live at `https://<project>.pages.dev`. Open that link on your
phone and **Add to Home Screen** to use it like a native app.

### Troubleshooting

**Build fails with "A compatibility_date is required when uploading a Worker."**
The project was created as a **Worker** and is running `npx wrangler deploy`, which
deploys a server Worker. This app is static — deploy it as **Pages** instead. Set the
project's build/deploy command to:

```bash
npx wrangler pages deploy . --project-name=fish
```

…or recreate it via the **Pages → Connect to Git** flow above, which has no deploy
command at all. Static Pages deploys never need a `compatibility_date`.

**Build fails with "Authentication error [code: 10000]" on a `/pages/projects/...` call.**
The build is using a custom `CLOUDFLARE_API_TOKEN` env var whose scope doesn't include
Pages (token permissions are separate from your account role). Fix it either way:

- **Cleanest:** use the native **Pages → Connect to Git** flow, which authenticates
  internally — no token or deploy command to manage.
- **Or** edit the token at <https://dash.cloudflare.com/profile/api-tokens> to add
  **Account → Cloudflare Pages → Edit**, then update the `CLOUDFLARE_API_TOKEN` env var.

1. Create a free Supabase project.
2. Run [`supabase_setup.sql`](./supabase_setup.sql) in the SQL Editor. It creates the
   `trips`, `spots`, and `catches` tables, a `photos` storage bucket, and row-level
   security policies.
3. Enable **Anonymous sign-ins** (Authentication → Sign In / Providers).
4. The project URL and anon public key are embedded in `index.html` (the `EMBED`
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
