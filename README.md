# TinyStatus

Tiny local health-check app for macOS.

Paste a domain, IP, `host:port`, Tailscale name, or JSON. TinyStatus infers the check kind and probes it.

- HTTP health (optional path discovery)
- TCP ports (including SSH tunnels that listen on localhost)
- Custom commands
- Tailscale hostnames
- ICMP-less “ping” (TCP connect)

Menu bar icon (green / red), a small window, sparkline, notifications. Settings include git backup of your config.

Requires **macOS 26+**. AppKit / Swift.

## Install and run

```bash
git clone https://github.com/duyet/tiny-status.git
cd tiny-status
make run
```

`make app` builds `TinyStatus.app`. `make run` builds and opens it.

## Config

Live file (legacy name): `~/.config/tiny-status/tunnels.json`

The payload is **`checks[]`**, not the old `tunnels` / `deployments` split. Copy from [`tunnels.example.json`](tunnels.example.json) or [`checks.example.json`](checks.example.json). `{home}` expands to your home directory.

```json
{
  "pollSeconds": 30,
  "checks": [
    { "id": "web", "title": "Web", "kind": "http", "url": "https://example.com/health" },
    { "id": "redis", "title": "Redis", "kind": "tcp", "host": "127.0.0.1", "port": 6379 },
    { "id": "ssh", "title": "Tunnel", "kind": "tcp", "host": "127.0.0.1", "port": 8443 },
    { "id": "ts", "title": "Peer", "kind": "tcp", "host": "my-machine.tailnet.ts.net", "port": 22 },
    { "id": "cmd", "title": "Custom", "kind": "command", "command": ["/usr/bin/true"] }
  ]
}
```

HTTP checks may set `"discover": true` to try, in order:

`/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health`

A TCP check is **up** if `host:port` accepts a connection. A command check is **up** if the process exits 0.

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
