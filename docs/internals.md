# Internals

Notes for agents and contributors. Keep [AGENTS.md](../AGENTS.md) short; put durable detail here.

Public repo: [github.com/duyet/tiny-status](https://github.com/duyet/tiny-status). macOS 26 AppKit. MIT. No Co-Authored-By. No secrets, tokens, private IPs, employer names, or real cluster names.

## Scope

Change only what the task asks. Do not rewrite Swift for style. Do not add speculative plugins.

## Layout

Single-target Swift. `Makefile` compiles `Sources/TinyStatus/*.swift` into `TinyStatus.app` (SwiftUI, AppKit, UserNotifications). No SPM package.

| File | Role |
|------|------|
| `App.swift` | `@main`. CLI vs `NSApplication` + `AppDelegate` |
| `AppDelegate.swift` | Menu bar, menus, toolbar, main window, import, settings host |
| `Store.swift` | `@MainActor` singleton: load, poll, alerts, import, patches, backup, prefs |
| `StatusController.swift` | AppKit `NSOutlineView` (main UI), `TableDensity`, cells |
| `Views.swift` | SwiftUI Settings (`ConfigWindow`). Some older card views are unused as the main window |
| `Check.swift` | `Check`, kinds, actions, tags, `CheckArt` |
| `Models.swift` | `Config`, alerts, backup, row types |
| `Probe.swift` | HTTP / TCP / command probes |
| `Discovery.swift` | Paste parse + `HealthDiscover` |
| `CLI.swift` | Subcommands, JSON stdout |
| `Support.swift` | `ConfigLoader`, `{vars}`, `DiskCache` |
| `Alerts.swift` | `AlertRule` / `AlertLogic` (pure, tested) and `AlertCenter` (notifications, actions, mute) |
| `Favicon.swift` | Favicon cache |
| `GitBackup.swift` | Git copy; `Shell` argv runner |
| `ImportController.swift` | Paste sheet |
| `SparkView.swift` | Heartbeat ticks, spark, bar chart |

TCP checks become `Store.tunnels`; HTTP and command become `Store.deploys`. Legacy `tunnels[]` / `deployments[]` still decode. The code does **not** rewrite those arrays to `checks[]` on load. CLI `rm` / `enable` still patch all three.

## Probe pipeline

- Interval: `pollSeconds` (default 30). `Timer` on the main actor; `tick()` reloads if the file mtime changed, then `poll()`.
- `poll()` copies enabled checks, then `Task.detached` + task group. `Probe.check` must stay off the main thread in the GUI.
- Skip `"enabled": false` and ids in `busy` (action in flight).
- CLI `probe` runs on the CLI thread (no detached task).

| Kind | Details |
|------|---------|
| TCP | Connect ~1.5s. No ICMP. If up, `lsof`/`ps` for listen pid. |
| HTTP | GET. 2xx and/or JSON `status`. Discover: 4s per path; explicit non-root 8s; non-discover 18s. Optional `k8s` / `k8sLive` argv each poll. |
| Command | `Shell.run`, 20s, exit 0. |

Origin write-back: `Store.resolveOrigins()` on GUI load; same `HealthDiscover.configure` on CLI `add` and import. First healthy path becomes `url`. If all HTTP fails and `ping != false`, kind becomes `tcp`.

HTTP 3xx is not healthy (`HTTP.isHealthy` is 2xx only). Do not shell-interpolate user strings (`Process.executableURL` = argv[0]).

## Config I/O

Live: `~/.config/tiny-status/tunnels.json`. Cache: `cache.json`. Favicons: `favicons/`.

`{vars}` on load: `{home}` `{user}` `{tmp}` `{config}` `{hostname}` `{env:NAME}` plus `"vars"` map. Saves are atomic, pretty-printed, sorted keys.

## CLI vs GUI

Same binary. Wrapper `scripts/tiny-status`. Shared: `ConfigLoader`, `Check`, `Probe`, `Discovery`, `DiskCache`. Not shared: `Store` timer, notifications, table UserDefaults (`TinyStatus.*`).

Commands: see [cli.md](cli.md). `add` infers kind, runs discover, stable id from host (`www.` stripped, lowercased). Duplicate id fails.

## UI facts

- Main table is AppKit, not SwiftUI. Autosave `TinyStatus.checks.v6`. Footer: `LinkStatus` (`NWPathMonitor` + `tailscale status --json`). Do not print Tailscale IPs.
- Density lives in Settings only. Relaxed = `.large` rows (`TableDensity`). Compact = `.small`.
- Sort by column headers only.
- `StatusCell`: checking = opacity pulse; status change = scale 0.25 → 1.06 → 1.
- Do not special-case product names for icons. Use `icon` / `image` / favicon.
- Nested JSON service symbols may still match substrings (`postgres`, `redis`); do not add more product cases.

## Tests

`make test` compiles all Swift **except** `App.swift` plus `Tests/Run.swift` into `.build/tiny-status-test`. Tiny `expect()` runner. No XCTest, no network. Logic change → update `Tests/Run.swift` in the same change.

CI (`.github/workflows/ci.yml`): `macos-latest`, `make test`, `make app`, CLI help, parse example JSON, upload `TinyStatus.app`.

## Release

`release-please-config.json`: simple, **`always-bump-patch`**, changelog `CHANGELOG.md`, extra file `Info.plist` (`x-release-please-version`). Manifest `.release-please-manifest.json`. Tags include `v`.

**Never auto-merge** `release-please--*` PRs (`chore(main): release …`). Human merges. Stay on **v0.1.x**. After a tag, a macOS job zips the app onto the GitHub release.

## Gotchas

- Examples must stay generic (`example.com`, `127.0.0.1`, `my-machine.tailnet.ts.net`).
- `TCP.canConnect` sets `AI_NUMERICHOST` — numeric IPs only in that helper; do not “fix” DNS there without tests.
- Discover vs explicit path: `/health` with `discover: false` does not walk other paths.
- First poll after launch does not alert (baseline in `AlertLogic.step`).
- Git backup editor defaults may use branch `master` while examples use `main` — Save writes the form.
- Makefile tests must not compile `App.swift` (two `@main`).
- Semantic commits if asked. Do not commit unless asked.
