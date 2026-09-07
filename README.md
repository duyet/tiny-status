# TinyStatus

macOS menu-bar and window app for local tunnels and HTTP health checks.

- Menu bar icon (green check / red x)
- Standalone window on launch and Dock reopen
- TCP probes (works even if another process opened the port)
- HTTP health JSON (`status`, `version`, `checks[]`)
- Optional kubectl image commands
- Health sparkline, version pills, notifications
- Settings window; git backup of your local config using your existing `git` / SSH / `gh` credentials

Requires **macOS 26+**.

```bash
git clone https://github.com/duyet/tiny-status.git
cd tiny-status
make run
```

## Config

Live config: `~/.config/tiny-status/tunnels.json`  
Copy from [`tunnels.example.json`](tunnels.example.json). `{home}` expands to your home directory.

```json
{
  "pollSeconds": 30,
  "tunnels": [
    {
      "id": "local",
      "title": "Local",
      "probeHost": "127.0.0.1",
      "probePort": 8080,
      "start": ["/usr/bin/true"],
      "stop": ["/usr/bin/true"]
    }
  ],
  "deployments": [
    {
      "id": "api",
      "title": "API",
      "healthUrl": "https://example.com/health",
      "openUrl": "https://example.com/health",
      "k8s": ["/usr/local/bin/kubectl", "get", "deploy", "api", "-o", "jsonpath={.spec.template.spec.containers[0].image}"],
      "k8sLive": ["/usr/local/bin/kubectl", "get", "pods", "-l", "app=api", "-o", "jsonpath={.items[0].spec.containers[0].image}"]
    }
  ]
}
```

A tunnel is **up** if `probeHost:probePort` accepts TCP. Start/stop/open commands are optional.

Health URL should return JSON with `status` (`healthy` / `degraded` / …) and optional `version` and `checks: [{ "service", "status" }]`.

## Git backup

Settings → **Git backup**. Copies the live config into a git repo (default `~/.config/tiny-status/git-backup`), then commit / pull --rebase / push. On conflict: Keep local or Keep remote. Uses your machine’s git remotes and credentials. Do not commit secrets.

## License

MIT
