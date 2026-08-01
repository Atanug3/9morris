# Supabase and Google Authentication Setup

This guide documents the complete backend and authentication setup for the hosted 9 Men's Morris game.

## Architecture

- **Cloudflare Workers** hosts the static website.
- **Supabase Auth** signs users in through Google or GitHub.
- **Supabase Postgres** stores online rooms and game state.
- **Supabase Realtime** sends room joins and moves to both devices.
- **Row Level Security (RLS)** restricts each game to its two participants.

Current production website:

```text
https://9morris-personal.atanug32123.workers.dev
```

Current Supabase project reference:

```text
ethefekgxcdsxhorfnnp
```

Supabase OAuth callback URL:

```text
https://ethefekgxcdsxhorfnnp.supabase.co/auth/v1/callback
```

## 1. Create the Supabase project

1. Sign in at [Supabase](https://supabase.com/).
2. Select **New project**.
3. Use the following settings:

| Setting | Selection |
|---|---|
| GitHub integration | Skip; Cloudflare already deploys this repository |
| Project name | `9morris-online`, or another descriptive name |
| Database password | Generate a strong password and save it in a password manager |
| Region | The available region closest to the expected players |
| Enable Data API | On |
| Automatically expose new tables | Off |
| Enable automatic RLS | On |
| Advanced configuration | Leave at its defaults |

4. Select **Create new project**.
5. Wait until database provisioning finishes.

The database password is an administrative secret. Do not place it in browser code, Git, documentation, chat, or Cloudflare variables.

## 2. Create the database schema

1. Open the Supabase project.
2. Select **SQL Editor**.
3. Select **New query**.
4. Copy the complete contents of `supabase-schema.sql`.
5. Paste it into the query editor.
6. Select **Run**.

Run the file as one complete query. It is designed to be safe to rerun when functions or policies need updating.

The script creates:

- The `public.games` table.
- The participant-only RLS policy.
- `create_game` for private room creation.
- `join_game` for assigning Player 2.
- `submit_game_state` for turn and revision-controlled updates.
- `leave_game` for explicitly abandoning a room.
- The `supabase_realtime` publication entry for `games`.

### Verify the schema

In **Database → Tables**, confirm that `games` exists.

In **Database → Policies**, confirm:

- RLS is enabled. The page should offer **Disable RLS**, not **Enable RLS**.
- `Participants can view their games` exists.
- The policy applies to `authenticated` users and the `SELECT` command.

In **Database → Functions**, confirm:

- `create_game`
- `join_game`
- `submit_game_state`
- `leave_game`

In **Database → Publications** or **Replication**, confirm that `games` is enabled under `supabase_realtime`.

The dashboard may label the table **API disabled** because direct anonymous access is intentionally unavailable. The game uses authenticated reads and restricted database functions.

## 3. Configure the browser connection

Open **Project Settings → API Keys**, or use the project **Connect** dialog.

Copy:

- The project URL.
- The **Publishable key**, beginning with `sb_publishable_`.

Set them in `supabase-config.js`:

```js
window.SUPABASE_CONFIG = {
  url: 'https://ethefekgxcdsxhorfnnp.supabase.co',
  anonKey: 'sb_publishable_REPLACE_WITH_THE_PROJECT_KEY',
};
```

The property is named `anonKey` for compatibility with the Supabase JavaScript client, but new projects should use the publishable key.

### Which values may be public?

Safe in browser code and Git:

- Supabase project URL.
- `sb_publishable_...` key.
- Legacy `anon` key, although Supabase is deprecating it.

Never expose:

- `sb_secret_...`
- `service_role`
- Database password
- Google OAuth client secret
- GitHub OAuth client secret

A browser application cannot keep its publishable key secret. Security comes from RLS, restricted grants, authenticated sessions, and carefully scoped database functions.

## 4. Configure Supabase redirect URLs

1. Open **Authentication → URL Configuration**.
2. Set **Site URL**:

```text
https://9morris-personal.atanug32123.workers.dev
```

3. Add this **Redirect URL**:

```text
https://9morris-personal.atanug32123.workers.dev/**
```

4. Save the settings.

The wildcard preserves invite parameters such as `?room=ABC123` after OAuth login.

For optional local testing, add:

```text
http://localhost:8000/**
```

Serve the project through a local HTTP server rather than opening `index.html` through a `file://` URL.

## 5. Create the Google Cloud OAuth project

### Create a dedicated Google Cloud project

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Open the project selector in the top navigation.
3. Select **New Project**.
4. Enter:
   - **Project name:** `9morris-auth`
   - **Organization:** No organization, when available
   - **Location:** Leave at the default
5. Select **Create**.
6. Select `9morris-auth` as the active project.

This project is only used for Google OAuth credentials. Basic Google login does not require Google Cloud compute resources.

## 6. Configure the Google consent screen

1. Open [Google Auth Platform](https://console.cloud.google.com/auth/overview).
2. Confirm `9morris-auth` is the selected project.
3. Select **Get started** if the Auth Platform has not been configured.
4. Enter:
   - **App name:** `9 Men's Morris`
   - **User support email:** An email address you monitor
   - **Audience:** External
   - **Developer contact email:** An email address you monitor
5. Complete the initial setup.

### Configure test users

While the app is in **Testing**:

1. Open **Audience**.
2. Find **Test users**.
3. Add every Google account that should test login.

Accounts that are not on this list cannot use Google login while the app remains in Testing.

### Configure scopes

1. Open **Data Access**.
2. Select **Add or remove scopes**.
3. Add or confirm only:
   - `openid`
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`
4. Save.

These are non-sensitive identity scopes. Do not add Gmail, Drive, Calendar, Contacts, or other permissions because this game does not need them.

## 7. Create the Google OAuth client

1. Open **Google Auth Platform → Clients**.
2. Select **Create client**.
3. Choose **Web application**.
4. Enter:
   - **Name:** `9morris-web`
5. Under **Authorized JavaScript origins**, add:

```text
https://9morris-personal.atanug32123.workers.dev
```

6. Under **Authorized redirect URIs**, add:

```text
https://ethefekgxcdsxhorfnnp.supabase.co/auth/v1/callback
```

7. Select **Create**.
8. Copy the Google **Client ID** and **Client secret**.

Do not open the Supabase callback URL directly. It only works during an OAuth flow, when Google supplies an OAuth state parameter. Opening it manually produces an expected `OAuth state parameter missing` error.

## 8. Enable Google in Supabase

1. Open **Supabase → Authentication → Sign In / Providers**.
2. Select **Google**.
3. Enable the provider.
4. Enter the Google client ID.
5. Enter the Google client secret.
6. Save.

The Google client secret belongs only in the Google and Supabase dashboards. Do not put it in `supabase-config.js`, Git, Cloudflare assets, or documentation.

## 9. Test Google login

1. Open an incognito/private browser window.
2. Visit:

```text
https://9morris-personal.atanug32123.workers.dev
```

3. Select **Continue with Google**.
4. Sign in with a configured test user.
5. Confirm that the game displays **Signed in as...**.
6. In **Supabase → Authentication → Users**, confirm that the user exists.

If the website URL still contains `?error=...`, remove the query parameters and reopen the clean URL before testing.

## 10. Allow any Google account

Testing mode restricts access to listed test users.

To allow any valid Google account:

1. Open **Google Auth Platform → Audience**.
2. Select **Publish app**.
3. Confirm the move to **Production**.

The app requests only non-sensitive identity scopes, so sensitive-scope verification should not be required. Google may still review branding information or show users that the consent screen has not been brand-verified.

For a polished public application, provide:

- A recognizable app name and logo.
- A support email.
- A homepage.
- A privacy policy.
- Terms of service.
- A verified custom domain, if available.

The free `workers.dev` domain is sufficient for functionality, but a custom verified domain improves user trust on the consent screen.

## 11. Optional GitHub authentication

1. Open [GitHub Developer Settings](https://github.com/settings/developers) using the personal GitHub account.
2. Select **OAuth Apps → New OAuth App**.
3. Enter:
   - **Application name:** `9 Men's Morris`
   - **Homepage URL:** `https://9morris-personal.atanug32123.workers.dev`
   - **Authorization callback URL:** `https://ethefekgxcdsxhorfnnp.supabase.co/auth/v1/callback`
   - **Enable Device Flow:** Off
4. Register the application.
5. Copy the client ID.
6. Generate and copy a client secret.
7. Open **Supabase → Authentication → Sign In / Providers → GitHub**.
8. Enable GitHub and enter both values.
9. Save.

GitHub does not use a test-user list. Any valid GitHub account can normally sign in after the provider is enabled.

Supabase automatically links Google and GitHub identities that expose the same verified email address. They become one Supabase user and therefore cannot act as both Player 1 and Player 2.

## 12. Deploy configuration changes

Cloudflare automatically builds from the personal GitHub repository.

Commit configuration and documentation:

```powershell
git add supabase-config.js supabase-schema.sql SETUP.md
git commit -m "Document Supabase and OAuth setup"
git push personal main
git push origin main
```

Never add `9morris-cloudflare.zip` to the commit.

The `.assetsignore` file publishes only browser assets. `supabase-schema.sql` and this guide remain in Git but are not served as website assets.

## 13. Test online multiplayer

Use two different Supabase users:

1. Device A signs in and creates a private room.
2. Device A copies the invite link.
3. Device B opens the link.
4. Device B signs in using a different verified email identity.
5. Device B selects **Join room** using the prefilled room code.
6. Confirm Device A changes from waiting to active.
7. Make alternating moves.
8. Confirm each board updates through Realtime or the polling fallback.

Incognito mode and separate devices do not create separate players if both OAuth accounts resolve to the same verified email.

## 14. Troubleshooting

### `OAuth state parameter missing`

Cause: The Supabase callback URL was opened directly.

Fix: Start login from **Continue with Google** or **Continue with GitHub** on the game website.

### Google says the user is not allowed

Cause: The OAuth app is in Testing and the account is not a test user.

Fix: Add the account under **Google Auth Platform → Audience → Test users**, or publish the app.

### Both devices appear as Player 1

Cause: Supabase linked Google and GitHub identities with the same verified email into one user.

Fix: Use a second account with a different verified email.

### `function gen_random_bytes(integer) does not exist`

Cause: An older version of `create_game` used an extension-dependent function.

Fix: Run the current complete `supabase-schema.sql` again. It uses `gen_random_uuid()`.

### Player 2 joins but Player 1 does not update

1. Confirm `games` is enabled under `supabase_realtime`.
2. Confirm the latest `script.js` is deployed.
3. Reload both devices.
4. Create a new room.

The application also polls every four seconds and reconnects automatically if Realtime is interrupted.

### `This room is no longer active`

The room has status `finished` or `abandoned`.

Create a new room. The current application abandons a room only when a participant explicitly selects **Leave room**.

### Room creation fails

1. Confirm the user is signed in.
2. Confirm all four database functions exist.
3. Rerun the complete current schema.
4. Review Supabase logs for the exact function error.

## Security checklist

- RLS is enabled on `public.games`.
- Only participants can select their game row.
- Anonymous users have no table access.
- Database writes use authenticated security-definer functions.
- Functions verify membership, turn ownership, game status, and revision.
- Only the publishable key is used by the browser.
- Secret/service-role keys are not committed.
- OAuth secrets exist only in provider and Supabase dashboards.
- Database password is stored only in a password manager.

The server checks authentication, membership, turn ownership, and concurrent revisions. Detailed Morris move legality is still validated by the browser, so online mode is intended for friendly play rather than adversarial or prize-based competition.
