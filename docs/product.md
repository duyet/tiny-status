# Product

TinyStatus is a **tiny local health-check app** for **macOS 26+**. You paste a domain, IP, `host:port`, Tailscale name, command, or JSON. The app infers a check kind and probes it on a timer.

Public repo: [github.com/duyet/tiny-status](https://github.com/duyet/tiny-status). MIT. Version line **v0.1.x** (patch only). Bundle id `net.duyet.tiny-status`.

## What it does

- One list of **checks** in `~/.config/tiny-status/tunnels.json` (legacy filename; the array is `checks[]`).
- Three kinds: **HTTP GET**, **TCP connect**, **command argv**.
- Menu bar (green / red / checking) plus a small window with a table, history ticks, and row actions.
- Notifications when a check fails or recovers.
- Optional git backup of the config file.
- The **same binary** is a CLI (`scripts/tiny-status` or `TinyStatus.app/Contents/MacOS/TinyStatus list`). No extra daemon. The GUI reloads the file on the next poll.

## Who it is for

People who keep a small local list of HTTP endpoints, localhost forwards (SSH tunnels), Tailscale peers, and one-off health scripts. Agents and scripts that want JSON against the same file the window already watches.

## What it is not

- Not a hosted status page or a cloud agent.
- Not ICMP. “Ping” means TCP connect to a port.
- Not a shell. Commands are argv arrays; the app does not run `sh -c` on user strings.
- Not a secret store. Do not put tokens, private IPs, or real cluster names in config or examples.
- Not a Kubernetes controller. Optional `k8s` / `k8sLive` argv only read image tags for a version column.
- Not a plugin marketplace. Plugins are out of scope until the core list is enough.

Appearance comes from per-check `icon` / `image` (or a fetched favicon). The app must not special-case product names in code.

## Core ideas

| Idea | Meaning |
|------|---------|
| Check | One row: `id`, `title`, `kind`, probe fields |
| HTTP | GET; 2xx and documented JSON `status` count as healthy; origin URLs can discover `/health`… |
| TCP | Connect only (works for SSH local forwards and Tailscale names) |
| Command | argv; exit 0 = up |
| Actions | Buttons / menu items: run argv or open a URL, optionally only when up or down |
| Vars | `{home}` `{user}` `{env:NAME}` and `"vars": { "key": "value" }` in strings |
| Enabled | `"enabled": false` keeps the row, skips probes |
| Alert | `"alert": false` mutes fail/recover for that row |

Examples in this repo use only generic hosts: `example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`.
