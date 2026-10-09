# TinyStatus verification map

Drive the built `TinyStatus.app`. One shared instance — never attach to a session you did not launch.

## Baseline

- `make app && open TinyStatus.app`
- `scripts/doctor.sh` must pass
- UserDefaults density defaults to `regular` when the key is unset

## Features

- [Density and toolbar checks](./density-toolbar.md)
- [Column sort](./column-sort.md)
- [Check actions](./check-actions.md)
