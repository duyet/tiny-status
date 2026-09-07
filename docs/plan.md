# Plan — unified checks

TinyStatus started as “tunnels + deployments”. It is now a **local health-check app**: one list of checks, smart paste, optional discovery.

## Phase 1 — Unified checks

- One `checks[]` array in config.
- Each item has `id`, `title`, `kind`.
- Kinds: `http`, `tcp`, `command`.
- Keep live filename `~/.config/tiny-status/tunnels.json`.
- Load old `tunnels` / `deployments` if present; map into `checks[]` once, then save the new shape.

## Phase 2 — Discovery

- HTTP `discover: true` (or paste of a bare host) tries:

  `/health` `/healthz` `/ready` `/live` `/ping` `/status` `/api/health` `/api/v1/health`

- First path that looks healthy wins; store the resolved `url`.
- TCP: no ICMP. “Ping” means connect to a port (default 80/443/22 as inferred).

## Phase 3 — UI import

- One paste field: URL, `host:port`, IP, Tailscale name, or JSON.
- Infer kind and fill `checks[]`.
- Merge JSON objects / arrays without dropping existing ids.
- Show inferred kind before save.

## Phase 4 — Programmable commands

- `kind: "command"` with argv `["/usr/bin/true"]` (no shell string).
- Optional later: timeout, cwd, env from config (never commit env secrets in examples).
- Exit 0 = up; capture short stderr for the UI.

## Phase 5 — Later: plugins

- Out of scope until 1–4 work.
- If added: load from a local folder, same `checks[]` shape, no network plugin install by default.

## Done when

- README matches the schema.
- Example JSON has only generic hosts.
- App can probe HTTP, TCP (localhost + Tailscale), and a command.
