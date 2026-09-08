# TinyStatus

Tiny local health-check app for macOS.

Paste a domain, IP, `host:port`, Tailscale name, or JSON. TinyStatus infers the check kind and probes it.

- HTTP health (optional path discovery)
- TCP ports (including SSH tunnels that listen on localhost)
- Custom commands
- Tailscale hostnames
- ICMP-less “ping” (TCP connect)

Menu bar icon (green / red), a small window, sparkline, notifications. Settings include git backup of your config.

Requires **macOS 26+**. AppKit / Swift. Version **v0.1.x** (patch-only). See [CHANGELOG.md](CHANGELOG.md).

## Install and run

```bash
git clone https://github.com/duyet/tiny-status.git
cd tiny-status
make run
```

`make app` builds `TinyStatus.app`. `make run` builds and opens it.

### CLI

The Mac app binary is also a CLI (no extra daemon). If the first argument is a command, it skips the GUI and prints JSON. Agents can add/remove checks and run Start/Stop against the same `tunnels.json` the app already reloads.

```bash
make cli
./scripts/tiny-status list
./scripts/tiny-status add https://example.com
./scripts/tiny-status add '{"url":"https://example.com","group":"homelab"}'
./scripts/tiny-status probe web
./scripts/tiny-status action ssh start
./scripts/tiny-status disable ssh
./scripts/tiny-status enable ssh
./scripts/tiny-status rm web
```

Or run `TinyStatus.app/Contents/MacOS/TinyStatus list`. Optional: `ln -sf …/scripts/tiny-status ~/.local/bin/tiny-status`.

Releases: conventional commits on `main` open a **release-please** PR that bumps **0.1.x** only, updates `CHANGELOG.md` and `Info.plist`. Merge that PR by hand (never `--auto`).

## Config

Live file (legacy name): `~/.config/tiny-status/tunnels.json`

The payload is **`checks[]`**, not the old `tunnels` / `deployments` split. Copy from [`tunnels.example.json`](tunnels.example.json) or [`checks.example.json`](checks.example.json).

Strings in titles, URLs, hosts, commands, tags, and backup paths expand `{variables}`:

| Token | Value |
|-------|--------|
| `{home}` | Home directory |
| `{user}` | Account name |
| `{tmp}` | Temp directory |
| `{config}` | `~/.config/tiny-status` |
| `{hostname}` | Machine name |
| `{env:NAME}` | Process environment |
| `{yourKey}` | From top-level `"vars"` |

```json
{
  "pollSeconds": 30,
  "vars": {
    "host": "example.com",
    "health": "https://{host}/api/v1/health"
  },
  "checks": [
    { "id": "web", "title": "Web", "kind": "http", "url": "{health}" },
    { "id": "redis", "title": "Redis", "kind": "tcp", "host": "127.0.0.1", "port": 6379 },
    { "id": "ssh", "title": "Tunnel", "kind": "tcp", "host": "127.0.0.1", "port": 8443 },
    { "id": "ts", "title": "Peer", "kind": "tcp", "host": "my-machine.tailnet.ts.net", "port": 22 },
    { "id": "cmd", "title": "Custom", "kind": "command", "command": ["/usr/bin/true"] },
    { "id": "script", "title": "Local script", "kind": "command", "command": ["{home}/bin/health.sh"] }
  ]
}
```

HTTP checks **auto-discover** when `url` is a site origin (`https://example.com`) or `"discover": true`. They try, in order:

`/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health` `/api/v1/healthz`

then the site root (2xx), then a TCP connect to 443/80 (no ICMP). Override the list globally with `"discoverPaths"` or per check with `"discoverPaths"` / `"discover": false` / `"ping": false`.

A TCP check is **up** if `host:port` accepts a connection. A command check is **up** if the process exits 0.

Set `"enabled": false` to keep a check in the list without probing it. Toggle from the table context menu, the menu bar, Settings, or `tiny-status disable <id>` / `enable <id>`.

Appearance and grouping come from the check, not from the title:

| Field | Meaning |
|-------|---------|
| `icon` | SF Symbol (default `network` / `globe` / `terminal` by kind) |
| `image` | Bundled name (`GitLab`) or a path (`{config}/logo.png`) for the menu bar and table |
| `tags` / `group` | Grouping. If omitted, tags are inferred from the title as a fallback |

Do not rely on the app special-casing a product name.

### Actions

Any check can declare `actions[]` — buttons in the table, row menu, and inspector. Each action runs an argv `command` or opens a `url`. `when` is `always` (default), `up`, or `down`. Optional `icon` (SF Symbol) and `confirm` (alert text before run).

Legacy `start` / `stop` / `open` argv fields still work if `actions` is omitted.

```json
{
  "id": "ssh",
  "title": "Tunnel",
  "kind": "tcp",
  "host": "127.0.0.1",
  "port": 8443,
  "actions": [
    { "id": "start", "title": "Start", "when": "down", "command": ["/usr/bin/true"] },
    { "id": "stop", "title": "Stop", "when": "up", "command": ["/usr/bin/true"] },
    { "id": "open", "title": "Open", "when": "up", "url": "https://example.com" }
  ]
}
```

Commands are argv arrays. The app does not interpolate them through a shell.

The table sorts by clicking a column header. Density defaults to **relaxed** (Settings → General). Toolbar Status and Group menus check the current value.

Optional HTTP JSON: `status` (`healthy` / `degraded` / …), `version`, `checks: [{ "service", "status" }]`.

### Kinds

| kind | Fields | Probe |
|------|--------|--------|
| `http` | `url`, optional `discover` | GET; optional path discovery |
| `tcp` | `host`, `port` | TCP connect (localhost tunnels, Tailscale, any IP) |
| `command` | `command` (argv array) | Exit code 0 = up |

### Smart import

Paste any of these in the UI (planned / in progress):

| Paste | Inferred |
|-------|----------|
| `https://example.com/health` | `http` |
| `example.com` | `http` + discover, or `tcp` 443 |
| `127.0.0.1:6379` | `tcp` |
| `my-machine.tailnet.ts.net` | `tcp` (often port 22) |
| JSON object / `checks[]` | merge into config |

No company hostnames in the repo examples. Use `example.com` and `127.0.0.1`.

## Git backup

Settings → **Git backup**. Copies the live config into a git repo (default `~/.config/tiny-status/git-backup`), then commit / pull --rebase / push. On conflict: Keep local or Keep remote. Uses your machine’s git remotes and credentials. Do not commit secrets.

## License

MIT
