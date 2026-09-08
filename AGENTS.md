# Agent notes — TinyStatus

Public repo: [github.com/duyet/tiny-status](https://github.com/duyet/tiny-status). macOS 26 AppKit app.

TinyStatus is a **tiny local health-check app**. Users paste a domain, IP, `host:port`, Tailscale name, or JSON. The app infers a check kind and probes it.

## Scope

Change only what the task asks. Do not rewrite Swift for style. Do not add speculative plugins.

## Config

- Live path: `~/.config/tiny-status/tunnels.json` (legacy filename).
- Config `{vars}`: `{home}` `{user}` `{tmp}` `{config}` `{hostname}` `{env:NAME}` plus `"vars": { "key": "value" }` and `{key}` in strings.
- Canonical array: **`checks[]`**.
- Example files in-repo: `tunnels.example.json`, `checks.example.json`.
- Examples must be generic: `example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`. **No company hosts, no kube contexts, no secrets.**

Kinds: `http` (`url`, optional `discover`), `tcp` (`host`/`port`), `command` (`command` argv).

Optional `actions[]` on a check: `{ id, title, command?, url?, when?, icon?, confirm? }`. `when` is `always` | `up` | `down`. Legacy `start`/`stop`/`open` argv still map to actions. `"enabled": false` skips probes (default true). Per-check `icon` (SF Symbol) and `image` (bundle name or path) drive the menu bar and table — do not special-case product names in code. `tags` / `group` drive grouping. Default table density is **relaxed** (`regular` in config). Density lives in Settings, not the toolbar. Sort by column headers (no sort toolbar).

HTTP origin URLs (or `discover: true`) try `discoverPaths` (default `/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health` `/api/v1/healthz`), then root 2xx, then TCP ping to 443/80. Per-check `discoverPaths` / `discover: false` / `ping: false` override.

## Probes

- TCP: connect only (works for SSH local forwards). No ICMP.
- HTTP: GET; treat 2xx (and documented JSON `status`) as healthy.
- Command: argv array, exit 0 = up. Do not shell-interpolate user strings.
- Keep probes off the main thread; poll using `pollSeconds`.

## UI

Menu bar + window. Import paste should infer kind. Do not show raw secrets. Keep copy simple English.

## CLI

Same binary as the app: `TinyStatus.app/Contents/MacOS/TinyStatus <cmd>` or `scripts/tiny-status`. Subcommands: `list` `get` `add` `rm` `probe` `action` `enable` `disable` `toggle` `config` `path`. `add` accepts JSON or a URL/host, auto-detects `/health` (then TCP ping), and writes the resolved fields. The GUI does the same on import and when it loads an origin-only HTTP check. JSON on stdout. Edits `~/.config/tiny-status/tunnels.json`.

## Public repo rules

- MIT. No Co-Authored-By.
- No secrets, tokens, private IPs, employer names, or real cluster names.
- Semantic commits if asked to commit. Do not commit unless asked.
- **release-please:** versions stay on `v0.1.x` (`versioning: always-bump-patch`). Changelog is `CHANGELOG.md`. **Never auto-merge** `release-please--*` PRs (`chore(main): release …`). Leave them for the human to merge.
- Docs live in `README.md`, this file, `docs/plan.md`.
