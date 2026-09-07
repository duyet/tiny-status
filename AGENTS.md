# Agent notes — TinyStatus

Public repo: [github.com/duyet/tiny-status](https://github.com/duyet/tiny-status). macOS 26 AppKit app.

TinyStatus is a **tiny local health-check app**. Users paste a domain, IP, `host:port`, Tailscale name, or JSON. The app infers a check kind and probes it.

## Scope

Change only what the task asks. Do not rewrite Swift for style. Do not add speculative plugins.

## Config

- Live path: `~/.config/tiny-status/tunnels.json` (legacy filename).
- Canonical array: **`checks[]`**.
- Example files in-repo: `tunnels.example.json`, `checks.example.json`.
- Examples must be generic: `example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`. **No company hosts, no kube contexts, no secrets.**

Kinds: `http` (`url`, optional `discover`), `tcp` (`host`/`port`), `command` (`command` argv).

HTTP `discover: true` tries `/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health`.

## Probes

- TCP: connect only (works for SSH local forwards). No ICMP.
- HTTP: GET; treat 2xx (and documented JSON `status`) as healthy.
- Command: argv array, exit 0 = up. Do not shell-interpolate user strings.
- Keep probes off the main thread; poll using `pollSeconds`.

## UI

Menu bar + window. Import paste should infer kind. Do not show raw secrets. Keep copy simple English.

## Public repo rules

- MIT. No Co-Authored-By.
- No secrets, tokens, private IPs, employer names, or real cluster names.
- Semantic commits if asked to commit. Do not commit unless asked.
- Docs live in `README.md`, this file, `docs/plan.md`.
