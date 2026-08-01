# 9 Men's Morris

A mobile-friendly browser implementation of 9 Men's Morris using HTML, CSS, and vanilla JavaScript.

## Game modes

- **One player vs Computer**
- **Two players on this device**
- **Two players online** using a private room code or invite link

All players must sign in with Google or GitHub. Online authentication, rooms, persistence, and realtime updates use Supabase.

## Rules

- During the **placement phase**, players take turns placing their 9 pieces.
- Forming a **mill** allows the current player to remove one opponent piece.
- During the **movement phase**, pieces move to adjacent connected positions.
- A player with only 3 pieces may **fly** to any open position.
- The same piece may move back and forth for at most two consecutive cycles.
- A player wins when the opponent has fewer than 3 pieces or no legal moves.

## Supabase setup

### 1. Create the database

1. Create a free project at [Supabase](https://supabase.com/).
2. Open **SQL Editor** in the Supabase dashboard.
3. Run the complete contents of `supabase-schema.sql`.

The script creates the `games` table, participant-only row-level security, room RPC functions, turn/revision checks, and the Realtime publication.

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
git add index.html styles.css script.js supabase-config.js supabase-schema.sql README.md .assetsignore
git commit -m "Add authenticated online multiplayer"
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

## Security note

Supabase enforces authentication, room membership, turn ownership, and optimistic revision checks. Morris move legality is also checked by the browser game engine; this project is intended for friendly play rather than adversarial or prize-based competition.
