# Agent notes — TinyStatus

Public repo: [github.com/duyet/tiny-status](https://github.com/duyet/tiny-status). macOS 26 AppKit app.

TinyStatus is a **tiny local health-check app**. Users paste a domain, IP, `host:port`, Tailscale name, or JSON. The app infers a check kind and probes it.

## Docs (read these)

| File | Use |
|------|-----|
| [docs/README.md](docs/README.md) | Index |
| [docs/product.md](docs/product.md) | What it is / is not |
| [docs/usage.md](docs/usage.md) | GUI, import, settings |
| [docs/config.md](docs/config.md) | `tunnels.json`, `checks[]`, vars |
| [docs/cli.md](docs/cli.md) | Same binary, JSON CLI |
| [docs/internals.md](docs/internals.md) | Architecture, probes, CI |
| [docs/plan.md](docs/plan.md) | Unification plan |
| [README.md](README.md) | Short user path |

## Scope

Change only what the task asks. Do not rewrite Swift for style. Do not add speculative plugins.

## Hard rules

- Live config: `~/.config/tiny-status/tunnels.json`. Canonical array **`checks[]`**.
- Examples: `example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`. **No company hosts, kube contexts, secrets.**
- TCP: connect only (no ICMP). HTTP: GET. Command: argv, exit 0. No shell interpolation. Probes off the main thread.
- Density in Settings (default relaxed / `regular`). Sort by column headers.
- Do not special-case product names for icons (`icon` / `image` / favicon).
- MIT. No Co-Authored-By. Semantic commits if asked. Do not commit unless asked.
- **release-please:** stay on **v0.1.x** (`always-bump-patch`). **Never auto-merge** `release-please--*` PRs.
