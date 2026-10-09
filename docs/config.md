# Config

Live file (legacy name): **`~/.config/tiny-status/tunnels.json`**.

Canonical array: **`checks[]`**. Old `tunnels[]` / `deployments[]` still load in memory; new writes should use `checks[]`.

If the file is missing, the app creates `~/.config/tiny-status/` and writes a starter JSON.

Also on disk:

| Path | Use |
|------|-----|
| `~/.config/tiny-status/cache.json` | Last probe snapshot (CLI `list` / `get`, first GUI paint) |
| `~/.config/tiny-status/favicons/` | HTTP favicons when `image` is omitted |

In-repo samples: [`tunnels.example.json`](../tunnels.example.json), [`checks.example.json`](../checks.example.json). Generic hosts only: `example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`. No company hosts, kube contexts, or secrets.

## Variables

Expanded in titles, URLs, hosts, commands, action fields, tags, group, icon, image, and backup paths.

| Token | Value |
|-------|--------|
| `{home}` | Home directory |
| `{user}` | Account name |
| `{tmp}` | Temp directory |
| `{config}` | `~/.config/tiny-status` |
| `{hostname}` | Machine name |
| `{env:NAME}` | Process environment (missing → empty) |
| `{yourKey}` | From top-level `"vars"` |

Custom vars can nest other tokens. Expansion happens on load, not on every probe of already-loaded structs.

```json
{
  "pollSeconds": 30,
  "vars": {
    "host": "example.com",
    "health": "https://{host}/health"
  },
  "checks": [
    { "id": "web", "title": "Web", "kind": "http", "url": "{health}" }
  ]
}
```

## Top-level keys

All optional except that you need some checks to probe.

| Key | Meaning | Default |
|-----|---------|---------|
| `pollSeconds` | Probe interval | `30` |
| `vars` | Custom `{key}` map | — |
| `groupBy` | `tag` \| `kind` \| `none` | `tag` |
| `density` | `regular` (relaxed) \| `compact` | `regular` |
| `groups` | Group header order | — |
| `order` | Check id order | — |
| `discoverPaths` | Global HTTP discovery list | built-in list below |
| `alerts` | Notifications | on, after 2 failed polls |
| `backup` | Git backup | off unless set |
| `checks` | Canonical list | — |
| `tunnels` | Legacy TCP | still loaded |
| `deployments` | Legacy HTTP | still loaded |

Ids are unique across the three arrays; `checks` wins if duplicated.

### `alerts`

```json
"alerts": { "enabled": true, "after": 2, "recover": true, "repeat": 1800, "quiet": "22:00-08:00", "sound": true }
```

| Field | Meaning | Default |
|-------|---------|---------|
| `enabled` | Master switch (Settings → General → Notifications) | `true` |
| `after` | Consecutive failed polls before alerting (debounces flaps) | `2` |
| `recover` | Notify on recovery, only if a down alert was sent | `true` |
| `repeat` | Seconds before re-alerting while still down. `0` = never | `0` |
| `quiet` | Local `HH:MM-HH:MM` window; alerts arrive without sound. May wrap midnight | — |
| `sound` | Play a sound | `true` |
| `onDown` | Notify on down | `true` |
| `onVersionDrift` | Notify when deploy and pod versions drift | `true` |

Per check, `"alert": false` mutes it. `"alert": { "after": 5, "repeat": 0 }` merges over the global fields (global `enabled: false` still wins).

Smart rules: the first poll after launch never alerts; while the network is offline, checks are not counted and one "Network offline" note is sent; 3+ checks down in the same poll send one grouped note; `degraded` counts as up; a tunnel start that ends `failed` alerts at once with exit code and stderr.

### `backup`

`enabled`, `autoOnSave`, `repo`, `file`, `remote`, `branch`, `remoteUrl`. Example repo: `{home}/.config/tiny-status/git-backup`.

## `checks[]`

Required: `id`, `title`, `kind` (`http` \| `tcp` \| `command`).

| Field | Kind | Meaning |
|-------|------|---------|
| `url` | http | Probe URL. Origin (`/` or empty path) triggers discovery unless `discover: false` |
| `host` / `port` | tcp | Connect target |
| `command` | command | argv array |
| `discover` | http | Force or skip path walk |
| `discoverPaths` | http | Per-check list (leading `/` added if missing) |
| `ping` | http | After paths fail, TCP to 443/80. Default on. `"ping": false` skips |
| `openUrl` | any | Browser target |
| `actions` | any | Buttons / menus |
| `start` / `stop` / `open` | any | Legacy argv if `actions` is empty |
| `tags` / `group` | any | Grouping. If omitted, tags may be inferred from the title |
| `icon` | any | SF Symbol. Defaults: `network` / `globe` / `terminal` |
| `image` | any | Bundle name (`GitLab`) or path (`{config}/logo.png`) |
| `enabled` | any | Missing or `true` = probe. `false` = skip |
| `alert` | any | Missing or `true` = notify. `false` = mute. Object = override `alerts` fields |
| `k8s` / `k8sLive` | http | Optional argv; stdout tag after last `:` is version |

### HTTP discovery

When `url` is a site origin or `"discover": true`, try in order:

`/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health` `/api/v1/healthz`

then the site root (2xx), then TCP to 443/80. First healthy HTTP path is stored as `url`. TCP fallback **changes kind to `tcp`**, clears `url`, sets `host`/`port`.

CLI `add`, GUI import, and GUI load of origin-only HTTP all run this and write the resolved fields.

### HTTP JSON the UI understands

Optional body fields: `status`, `healthy` (bool), `version`, `uptime_seconds`, `checks[]` with `service` or `name`, `status`, `response_time_ms` or `latency_ms`.

Healthy JSON `status`: `healthy`, `ok`, `up`, `pass`, `passing`, `success`. Unhealthy JSON `status` wins over HTTP 2xx.

### Actions

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

`when`: `always` (default) \| `up` \| `down`. Optional `icon` (SF Symbol), `confirm` (alert text; CLI needs `--yes`). Commands are argv. No shell interpolation.

If `actions` is omitted, legacy `start` → Connect (when down), `stop` → Disconnect (when up), `open` → Open (when up). Custom `actions[]` wins; legacy is not merged on top.

### Legacy arrays

`tunnels[]` → tcp: `probeHost` (default `127.0.0.1`), `probePort`, `start`/`stop`/`open`.  
`deployments[]` → http: `healthUrl` → `url`, plus `k8s` / `k8sLive` / `openUrl`.

## Probe rules

| Kind | Probe | Up when |
|------|--------|---------|
| `http` | GET | 2xx and/or documented JSON `status` |
| `tcp` | Connect (~1.5s). No ICMP | Port accepts a connection |
| `command` | argv, 20s timeout | Exit 0. Empty command → `["/usr/bin/true"]` |

Keep probes off the main thread in the GUI. Poll with `pollSeconds`.

## Defaults worth remembering

| Topic | Default |
|-------|---------|
| Poll | 30s |
| Density | relaxed (`regular`) |
| Group by | tag |
| Hidden column | Group |
| Spark | last 40 polls |
| `enabled` / `alert` | true |
| Alert after | 2 failed polls |
| Alert repeat | never |
| HTTP discover on origin | on |
| TCP fallback after HTTP | on |
| macOS | 26+ |
