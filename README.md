# 9 Men's Morris

A mobile-friendly browser implementation of 9 Men's Morris using HTML, CSS, and vanilla JavaScript.

See [SETUP.md](SETUP.md) for the complete Supabase, Google OAuth, GitHub OAuth, and deployment guide.

## Game modes

- **One player vs Computer**
- **Two players on this device**
- **Two players online** using a private room code or invite link

All players must sign in with Google or GitHub. Online authentication, rooms, persistence, and realtime updates use Supabase.

## Rules

- Players initially take turns placing pieces on empty points.
- After placing their first **3 pieces**, a player may either place another piece or move
  one existing piece to an adjacent connected point on each turn.
- Forming a **mill** allows the current player to remove one opponent piece.
- Placement continues until each player has placed all 9 pieces; movement remains
  available throughout this mixed stage.
- A player with only 3 pieces may **fly** to any open position only after all their pieces
  have been placed.
- The same piece may move back and forth for at most two consecutive cycles.
- A player wins when the opponent has fewer than 3 pieces or no legal move after placing
  all their pieces.

## Supabase setup

### 1. Create the database

1. Create a free project at [Supabase](https://supabase.com/).
2. Install the Supabase CLI and link the project.
3. Apply the repository migrations with `supabase db push`.

See [SETUP.md](SETUP.md) for the complete migration and baseline procedure.

### 2. Configure the website

Open **Project Settings > API** in Supabase and copy the project URL and public anon/publishable key into `supabase-config.js`:

```js
window.SUPABASE_CONFIG = {
  url: 'https://YOUR_PROJECT.supabase.co',
  anonKey: 'YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY',
};
```

The anon/publishable key is intended for browser use and is protected by row-level security. Never put a service-role key or OAuth client secret in this file.

### 3. Configure redirect URLs

In **Supabase > Authentication > URL Configuration**:

- Set **Site URL** to the deployed Cloudflare URL.
- Add the deployed URL to **Redirect URLs**.
- For local development, optionally add `http://localhost:8000/**`.

### 4. Enable Google login

1. Create a Web OAuth client in [Google Cloud Console](https://console.cloud.google.com/apis/credentials).
2. Use the callback URL shown under **Supabase > Authentication > Providers > Google**.
3. Enter the Google client ID and secret in the Supabase Google provider settings.
4. Enable the provider.

### 5. Enable GitHub login

1. Open GitHub **Settings > Developer settings > OAuth Apps**.
2. Create an OAuth app using the deployed website as its homepage.
3. Use the callback URL shown under **Supabase > Authentication > Providers > GitHub**.
4. Enter the GitHub client ID and secret in Supabase.
5. Enable the provider.

OAuth secrets stay in the provider and Supabase dashboards; they are never committed to this repository.

## Cloudflare deployment

The repository includes `wrangler.jsonc` and `.assetsignore`. Cloudflare deploys only:

- `index.html`
- `styles.css`
- `script.js`
- `supabase-config.js`

Push a configured version to both repositories:

```powershell
git add index.html styles.css script.js supabase-config.js README.md SETUP.md `
  supabase tests .assetsignore
git commit -m "Add server-authoritative online multiplayer"
git push personal main
git push origin main
```

The personal repository triggers the automatic Cloudflare deployment.

## Online gameplay

1. Both players sign in with Google or GitHub.
2. Player 1 selects **Two players online** and creates a private room.
3. Player 1 shares the six-character code or invite link.
4. Player 2 opens the link, selects **Two players online**, and joins the room.
5. Moves synchronize automatically across both devices.

Players can reload an active room using its invite URL.

## Tests

With the local Supabase Docker stack running:

```powershell
.\tests\run-local.ps1
```

This runs the browser action-boundary test and the pgTAP database rule/security suite.
See [SECURITY_TEST_PLAN.md](SECURITY_TEST_PLAN.md) for staging, production, privacy,
concurrency, abuse, and go-live coverage.

## Git hooks

This repo ships versioned hooks in `.githooks/` (e.g. a `pre-commit` that warns on binary files and blocks files over 100 MB). Git does not auto-enable hooks from a custom path, so after cloning run this once:

```bash
git config core.hooksPath .githooks
```

See [.githooks/README.md](.githooks/README.md) for details.

## Security note

For online games, Supabase computes the resulting state from a small action (`place`, `move`, or `remove`). It enforces authentication, room membership, turn ownership, revision ordering, adjacency, flying, repetition, mills, captures, phase changes, and wins. The browser cannot replace the stored board.
