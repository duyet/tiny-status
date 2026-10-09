# Check actions

A check can declare `actions[]` in config. Buttons appear in the Actions column, the row context menu, and the inspector. `when` of `up` / `down` hides buttons that do not apply.

## Sub-features

- `actions-column` — Start / Stop / Open (or custom titles) render for checks that define actions
- `when-filter` — Start shows when down; Stop when up
- `legacy` — `start` / `stop` / `open` argv still produce buttons if `actions` is omitted
- `url-action` — an action with `url` opens that URL instead of running a command

## How to get to it (user POV)

- Actions column on a check row
- Right-click the row
- Settings → Checks → inspector Actions section

## Driving it with osascript

Preconditions: config includes the example Tunnel check with `actions` (see `tunnels.example.json`). Prefer a copy in a throwaway file; do not rewrite the user's live config unless they already have this shape.

- Action: look at a down tunnel row. Result: Start visible, Stop hidden.
- Action: look at an up tunnel row. Result: Stop (and Open if `when` is `up`) visible.
- Action: click Start. Result: command runs off the main thread; row shows busy then re-probes.

## Gotchas

- Example commands use `/usr/bin/true` — they will not actually bind a port.
- Do not put real hosts or secrets in proof screenshots destined for the public repo.
