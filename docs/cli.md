# CLI

The Mac app binary is also a CLI. If the first argument is a command, it skips the GUI and prints JSON. No extra daemon. Edits `~/.config/tiny-status/tunnels.json`. The GUI reloads that file on its next poll.

```bash
make cli
./scripts/tiny-status list
TinyStatus.app/Contents/MacOS/TinyStatus list
```

`scripts/tiny-status` runs `make app` if the binary is missing, then `exec`s it.

Force GUI even if the binary is named `tiny-status`: `--gui`. Treat as CLI: first arg `cli` / `--cli`, or a known command.

Unknown command: exit **2**. `probe` or a failed action: exit **1**. Errors: `{"ok": false, "error": "…"}`.

## Commands

| Command | What it does |
|---------|----------------|
| `list` / `ls` | Checks + last **cached** status (not a live probe) |
| `get <id>` | One check + cache |
| `add <json\|url\|host>` | Add; auto-detects `/health` and writes resolved fields |
| `add -` | Read JSON or URLs from stdin (also if no args) |
| `rm` / `remove` / `delete` `<id>` | Remove from `checks` / `tunnels` / `deployments` |
| `probe` / `check` `[id]` | Live probe now. No id → enabled checks only. Exit 1 if any are down |
| `action` / `run` `<id> <name> [--yes]` | Run an action (`start`, `stop`, `open`, or custom) |
| `enable` / `disable` / `toggle` `<id>` | Skip or resume probes |
| `config` | Print the live file |
| `path` | Print the config path |
| `version` / `-v` | `{ "name": "tiny-status", "version": "…" }` |
| `help` / `-h` | Usage on stderr |

`add` fails if the id already exists. Confirmable actions need `--yes`. Set `TINYSTATUS_CLI_NO_OPEN` in tests to skip actually opening URLs.

## Examples

```bash
./scripts/tiny-status list
./scripts/tiny-status get web
./scripts/tiny-status add https://example.com
./scripts/tiny-status add '{"url":"https://example.com","group":"homelab"}'
./scripts/tiny-status add '{"id":"redis","title":"Redis","kind":"tcp","host":"127.0.0.1","port":6379}'
./scripts/tiny-status add '{"id":"ts","kind":"tcp","host":"my-machine.tailnet.ts.net","port":22}'
echo '{"url":"https://example.com/health"}' | ./scripts/tiny-status add -
./scripts/tiny-status probe
./scripts/tiny-status probe web
./scripts/tiny-status action ssh start
./scripts/tiny-status disable ssh
./scripts/tiny-status enable ssh
./scripts/tiny-status rm web
```

`add` infers kind the same way as Import (URL, `host:port`, hostname, JSON). Origin HTTP walks discover paths, then root, then TCP. Extra TCP rows for the same HTTP host are dropped. See [config.md](config.md) and [usage.md](usage.md).
