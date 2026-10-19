# Multiple Claude accounts — design

Date: 2026-10-19
Status: draft, awaiting approval

## Why

The user now has two Claude subscriptions and works across both. UsageTracker reads one
login — the `Claude Code-credentials` keychain item — so it only ever shows whichever
account Claude Code is signed into. The user wants to glance at the popover and know how
much room each account has left, so they can pick which one to work in.

## How the user will run two accounts

One Claude Code config folder per account, both signed in at the same time:

- `~/.claude` — one account (plain `claude`)
- `~/.claude-2` — the other (`alias claude2='CLAUDE_CONFIG_DIR=$HOME/.claude-2 claude'`)

Shared setup (`CLAUDE.md`, `settings.json`, `agents`, `hooks`, `plugins`, `skills`,
`projects`) is symlinked from `~/.claude` into `~/.claude-2`, so both accounts write the same
transcripts. The user sets this up after the app supports it; the final end-to-end test
depends on it.

Rejected: switching with `/logout` + `/login`. The old account's login leaves the keychain on
every switch, so the app would have to hold and refresh its own copies of logins, and it is
unknown whether `/logout` revokes them server-side.

## Goals

1. Every signed-in Claude Code account on the Mac gets its own full Claude card in the
   popover — the same rows as today's card (Session, Weekly, per-model limits, extra
   credits and buckets), its own drill-in page, reorderable and collapsible on its own.
2. Accounts are found automatically. Nothing to add in Settings.
3. With two or more accounts, each card title is "Claude · <name>". The name defaults to the
   account's email; the user can rename it in Settings. With one account, the title stays
   plain "Claude" as today. Most users of this public app have one account, and an email in
   every title would show up in every screenshot they share.
4. An account whose numbers are stale — its access token expired because that account's
   Claude Code hasn't run for ~8h — keeps showing its last known numbers, marked with their
   age ("as of 9h ago"). This survives quitting and relaunching the app. A limit whose reset
   time has passed since the last reading shows as reset, not its old percentage.
5. The menu bar works exactly like today: the user pins one row and the ring shows it. Any
   row on any Claude card can be pinned.
6. Each account has its own Claude page in the Settings sidebar, with a name field.
7. Any number of accounts, not hardcoded to two.

## Non-goals

- Switching Claude Code between accounts from inside UsageTracker.
- Per-account cost estimate and insights. Transcripts do not record which account ran them
  (checked 2026-10-19: no account or email field at the top level of a transcript line), and
  both folders share `projects`. Est. API cost, 24h insights, top skills/agents, and today
  stats appear on **one** card only, labeled as covering this Mac, all accounts.
- Supporting the logout/login workflow (holding copies of logins).
- Config folders outside the home-folder `~/.claude*` pattern. No "add folder" UI.
- Setting up `~/.claude-2` itself.

## Anti-goals — failure even if everything else works

- **Writing to or refreshing any `Claude Code-credentials*` keychain item.** This applies to
  every account's item, not only the default one. Writing evicts `apple-tool:` from the
  item's partition list and makes every Claude Code read prompt for the keychain password.
  Reads go through `/usr/bin/security` only, never `SecItemCopyMatching`. See "Known Issues"
  in `CLAUDE.md`.
- Any keychain password prompt, ever.
- One account's numbers on another account's card. The claude.ai cookie fallback is the
  obvious way this happens.
- Breaking the current single-account setup: the existing pinned row, provider order, and
  enabled toggle for the `claude` provider must carry over untouched. Collapse state isn't
  saved today (`Provider.isExpanded` lives only in memory), so there's nothing to migrate.
- Breaking cookie-only users. The README section "Using Claude without Claude Code",
  onboarding, How It Works, and `ProviderPage` all offer the claude.ai cookie as a way in
  without the CLI.
- More load on `api.anthropic.com/api/oauth/usage` per account than today. Each account is
  polled on the existing refresh interval (≥5 min). A 429 from that endpoint looks like
  "No usage data / Sign in", so over-polling creates fake sign-in errors.
- The 21 leftover `Claude Code-credentials-<hash>` items already in the user's keychain
  showing up as phantom accounts. Most likely they belong to deleted temp folders.

## Known facts and constraints

- **Keychain naming.** The default config folder uses `Claude Code-credentials`. A custom
  `CLAUDE_CONFIG_DIR` uses `Claude Code-credentials-<8 hex chars>`. **Not verified:** how the
  suffix is derived. A likely guess is the first 8 hex of a SHA-256 of the config folder
  path. The builder must pin it down and confirm it against the user's real `~/.claude-2`
  login. The Claude Code binary (`~/.local/share/claude/versions/<v>`) stores strings
  length-prefixed, so plain string search did not find the naming code.
- **Account identity.** The config file's `oauthAccount` object carries `emailAddress`,
  `accountUuid`, `organizationUuid`, `displayName`, and `organizationName`. For the default
  folder that file is `~/.claude.json`, outside `~/.claude`. For a custom folder it is
  assumed to be `$CLAUDE_CONFIG_DIR/.claude.json`. **Not verified.**
- **File credentials.** Newer CLI versions may store credentials in
  `<config folder>/.credentials.json` instead of the keychain. `ClaudeProvider` already reads
  `~/.claude/.credentials.json`. Each folder follows the same rule. That file is the only
  store the app may write refreshed tokens to.
- **Hardcoded provider ID.** `"claude"` appears in about 20 places: the `App.swift` refresh
  table, `ClaudeProvider`, `ClaudeWebProvider`, `ProviderCatalog`, `ProviderPage`,
  `HowItWorksPage`, `Models.swift` defaults, `MenuBarView`, `ClaudeDetailView`, and
  `ProviderRow`. `PinnedItem` is `(providerId, itemLabel)`. The default account keeps ID
  `claude`. Extra accounts need IDs that stay the same across relaunches and re-logins.
- **Last-known data.** `UsageCache` already restores providers at launch. `carriedForward`
  keeps last-known data when a fetch fails, but drops data that has "aged out". An idle
  account whose token simply expired must not age out.
- **Web cookie.** `~/.usagetracker/claude-web.json` holds one claude.ai cookie for one
  account. The field stays on the default Claude Settings page. Three cases:
  - **No CLI login anywhere:** the cookie drives the `claude` card exactly as today. There is
    no other card it could leak into.
  - **CLI logins exist:** the cookie fills in only for the card whose account it belongs
    to. A likely way to match is by org UUID, from `/api/organizations` against
    `oauthAccount.organizationUuid`. If the app can't tell, it fills in for no card.
  - **The cookie's account has no folder, but other folders do:** ignore the cookie; it gets
    no card of its own. This isn't a regression, since today that cookie only appears as the
    cross-account fallback this design forbids.
- **Cached readings carry their account.** Tag cached and carried-forward readings with
  `accountUuid`, so stale numbers can't move to another card. This matters if `~/.claude` is
  later signed in to a different account.

## Decided

| Decision | Whose |
|---|---|
| Separate config folder per account, both signed in | User agreed to the recommendation |
| Layout A: a separate full card per account (B, accounts stacked in one card, and C, side by side, rejected) | User, from mockups |
| Menu bar exactly like today | User |
| Name defaults to the email, renamable | Suggested; user agreed |
| Automatic discovery | Suggested; user agreed |
| Shared transcript stats on one card, labeled "this Mac, all accounts" | Suggested; user agreed |
| No "in use" chip; a stale-age marker instead (with both accounts signed in, "in use" means nothing) | Designer's call |
| Rows whose reset time has passed show "reset" | Designer's call |
| One Settings page per account | Designer's call |
| Any number of accounts | Designer's call |
| One account keeps the plain "Claude" title; the email appears only with 2+ | Designer's call, from the builder check |
| Cookie-only users keep a `claude` card as today | Designer's call, from the builder check (keeps a shipped, documented path working) |

## Left to the builder

- How discovery finds candidate folders (`~/.claude`, `~/.claude-*`) and confirms each one
  has a login, without dumping the whole keychain. Folder-first discovery also keeps the
  leftover hash items out on its own.
- The ID scheme for extra accounts, and what happens if the same account is signed in
  through two folders. Suggestion: one card per `accountUuid`.
- Where the name override is stored. Suggestion: `config.json`.
- Which card carries the shared stats (suggestion: the default `claude` card) and the exact
  label wording. Suggestion: read transcripts from every discovered folder, deduplicated by
  real path, so "all accounts" stays true even for a folder that isn't symlinked.
- How "as of 9h ago" and "reset" render. Use the existing tokens in `UsageDesign.swift`.
- Test structure.

## How to check it's done

1. `make test` passes.
2. Unit tests cover:
   - the keychain suffix rule
   - discovery ignoring leftover hash items and folders with no login
   - stable account IDs
   - old config migration (an existing `claude` pin still pins the same row)
   - the cookie fallback never crossing accounts
   - stale data surviving relaunch
3. End to end, after the user signs in to `~/.claude-2`:
   - two Claude cards appear, each with its own email
   - no keychain prompt appears, and the securityd partition-mismatch log query from
     `CLAUDE.md` shows nothing new
   - a row pinned from the second card shows in the menu bar ring
   - after quitting and relaunching, both cards come back with their numbers
