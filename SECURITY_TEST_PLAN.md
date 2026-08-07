# Security and Privacy Test Plan

## Scope and trust boundaries

The browser and every value it sends are untrusted. Cloudflare serves static assets.
Supabase Auth establishes identity, Postgres is the authority for room membership and
game rules, and Realtime is only a notification channel. The public Supabase
publishable key is not a secret.

Protected assets:

- OAuth identities and sessions.
- Participant names and room membership.
- Private room codes and game state.
- Turn order, revisions, moves, captures, and results.
- Supabase administrative credentials and OAuth provider secrets.

## Required security properties

1. Only authenticated participants can read a game.
2. Clients cannot insert, update, or replace game state directly.
3. Game creation always starts from the canonical server-generated state.
4. Every action is authorized against the stored player, turn, status, and revision.
5. Placement, movement, flying, mills, captures, repetition, and wins are computed by
   Postgres.
6. Stale, duplicated, concurrent, malformed, and out-of-turn actions fail safely.
7. Realtime does not disclose rows that RLS would hide.
8. Browser rendering treats provider display names and database text as text, not HTML.
9. Only publishable configuration is deployed; secrets remain outside Git and assets.
10. Collected identity data is minimal and has a documented deletion and retention path.

## Automated repository tests

| ID | Test | Expected result | Location |
|---|---|---|---|
| AUTH-01 | Call action RPC without an authenticated subject | Rejected | pgTAP |
| AUTH-02 | Submit an action as a non-participant | Rejected | pgTAP |
| RLS-01 | Select a game as a non-participant | Zero rows | pgTAP |
| RLS-02 | Check anonymous read and authenticated update grants | Denied | pgTAP |
| API-01 | Check private helper schema access | Denied | pgTAP |
| API-02 | Check legacy whole-state RPC | Absent | pgTAP |
| INIT-01 | Create a room with a forged initial board and winner | Canonical empty board is stored | pgTAP |
| RULE-01 | Legal placement and alternating turns | Accepted | pgTAP |
| RULE-02 | Out-of-turn placement | Rejected | pgTAP |
| RULE-03 | Move before placing three pieces | Rejected | pgTAP |
| RULE-04 | Adjacent move after placing three while placement remains | Accepted | pgTAP |
| RULE-05 | Non-adjacent move before all pieces are placed | Rejected | pgTAP |
| RULE-06 | Placement remains available after three pieces | Accepted | pgTAP |
| RULE-07 | Flying with exactly three pieces after all are placed | Accepted | pgTAP |
| RULE-08 | Third back-and-forth cycle | Rejected | pgTAP |
| RULE-09 | Mill creation and capture authorization | Enforced | pgTAP |
| RULE-10 | Capture a mill piece while another piece is available | Rejected | pgTAP |
| RULE-11 | Capture when all opponent pieces are in mills | Accepted | pgTAP |
| RULE-12 | Winning capture | Winner and finished status recorded | pgTAP |
| INPUT-01 | Missing, non-numeric, out-of-range, or unknown action values | Rejected without mutation | pgTAP |
| REV-01 | Replay an old revision | Rejected | pgTAP |
| LIFE-01 | Submit an action after game completion | Rejected | pgTAP |
| WEB-01 | Online browser action before server response | Local board remains unchanged | Node |
| WEB-02 | Inspect online RPC payload | Action only; no replacement state | Node |
| WEB-03 | Apply authoritative RPC response | Returned state becomes visible | Node |

Run:

```powershell
supabase start
.\tests\run-local.ps1
```

## Staging and production tests

These tests require real OAuth sessions, HTTP, Realtime, or platform controls and are
not fully represented by direct SQL tests.

| ID | Priority | Procedure | Expected result |
|---|---|---|---|
| OAUTH-01 | P0 | Sign in through Google and GitHub with different verified emails | Two distinct Supabase users are created |
| OAUTH-02 | P0 | Sign in through both providers using the same verified email | Identities link to one user and cannot occupy both seats |
| OAUTH-03 | P0 | Cancel OAuth, alter callback parameters, and use an unapproved redirect | No session is issued; redirect stays on the allowlist |
| SESSION-01 | P0 | Sign out on one device, then replay its previous access token after expiry | Expired/revoked session cannot read or act |
| HTTP-01 | P0 | Use REST with anon, outsider, Player 1, and Player 2 tokens | Responses match RLS and RPC authorization |
| RACE-01 | P0 | Send two valid actions concurrently with the same revision | Exactly one commits; the other gets a stale-revision error |
| RACE-02 | P0 | Delay and reorder Realtime updates around a mill and capture | UI never rolls back to an older revision |
| RT-01 | P0 | Subscribe as an outsider to a known game ID | No game payload is received |
| ROOM-01 | P1 | Try random and sequential room codes at controlled rate | No row data leaks; monitoring detects enumeration |
| ROOM-02 | P1 | Attempt to join the same waiting room concurrently from two accounts | One Player 2 wins; the other is rejected |
| LEAVE-01 | P1 | Explicitly leave, then try read/action/rejoin flows | Status and access match the documented abandonment policy |
| XSS-01 | P0 | Use OAuth/display names containing HTML, quotes, and Unicode controls | Rendered as text; no script or markup executes |
| CDN-01 | P1 | Block or tamper with the Supabase CDN script in a test environment | App fails closed with a clear configuration/loading error |
| DOS-01 | P1 | Burst create, join, refresh, and action RPCs within an approved test limit | Rate controls and alerts prevent sustained abuse |
| SECRET-01 | P0 | Inspect Git history, Cloudflare assets, source maps, Actions logs, and variables | No database password, service role key, or OAuth secret appears |
| MIG-01 | P0 | Run migrations against a fresh local database and a disposable staging project | Same schema, grants, policies, functions, and tests pass |
| ROLLBACK-01 | P1 | Exercise the documented rollback on staging | Service returns to a known compatible version without data loss |

## Privacy tests

| ID | Procedure | Expected result |
|---|---|---|
| PRIV-01 | Review Google scopes and GitHub permissions | Only identity, email, and profile data are requested |
| PRIV-02 | Inspect `games`, Auth users, logs, backups, and analytics | No unnecessary profile or gameplay data is collected |
| PRIV-03 | Delete a test account using the documented support/admin path | Identity and associated game data follow the declared deletion policy |
| PRIV-04 | Verify retention settings for finished/abandoned games and platform logs | Retention period is documented and enforced |
| PRIV-05 | Inspect browser local/session storage, IndexedDB, cookies, and URL history | Tokens use Supabase defaults; room codes are not retained unnecessarily |
| PRIV-06 | Review error and audit logs after failed attacks | Tokens, OAuth codes, email addresses, and full payloads are not exposed |

## CI security requirements

- Pull requests run the browser test, fresh database reset, and pgTAP suite.
- Production migration deployment uses protected encrypted secrets and a protected
  environment.
- Workflow permissions are read-only except where deployment requires more.
- Untrusted pull-request code never receives production Supabase secrets.
- Migration deployment is serialized and followed by `supabase migration list`.
- Dependency versions, including the Supabase CLI, are pinned and updated deliberately.

## Go-live exit criteria

- All P0 tests pass against staging and the production configuration.
- A clean `supabase db reset` and `.\tests\run-local.ps1` pass.
- No whole-state mutation path or direct authenticated table write exists.
- RLS and Realtime isolation pass with a third, non-participant identity.
- Concurrent same-revision actions produce exactly one committed update.
- Secret scanning finds no administrative or OAuth secrets.
- Privacy policy states identity data, game data, retention, deletion, and contact details.
- Rate-limit monitoring and an operational rollback procedure are available.

## Residual risks

- Six hexadecimal room-code characters provide about 16.8 million combinations; without
  rate limiting, online guessing remains possible even though RLS prevents reading a room
  before joining.
- A static browser application depends on Supabase Auth/CDN availability and client-side
  supply-chain integrity.
- Account deletion, retention automation, abuse monitoring, and platform rate limits
  require operational configuration outside this repository.
