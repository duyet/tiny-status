# Density and toolbar checks

The table uses regular row size unless the user picks Compact. Status, Group, and Density toolbar menus show a check on the current value. There is no Sort toolbar item.

## Sub-features

- `default-regular` — first launch without the density key uses regular rows
- `toolbar-check` — Density menu checks Regular or Compact to match the current mode
- `no-sort-toolbar` — toolbar customization / default items omit Sort

## How to get to it (user POV)

- Toolbar Density button
- View → Density
- View → Filter Status / Group By (same checkmark pattern)

## Driving it with osascript

Preconditions: app launched by this run, window visible.

- Action: View → Density. Result: one of Compact / Regular has `value` checked; it matches `defaults read net.duyet.tiny-status TinyStatus.density` (or Regular if unset).
- Action: choose Compact, then Regular. Result: row height changes; the newly chosen item is checked.
- Action: inspect toolbar. Result: no control labeled Sort.

## Gotchas

- An old UserDefaults `compact` value overrides the new default. Unset the key to prove default-regular.
- Toolbar customization can hide Density; restore default toolbar items first.
