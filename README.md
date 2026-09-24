# sing-box-dashboard (Omarchy Shell Plugin)

A native [Omarchy](https://omarchy.org/) status bar widget and control panel for [sing-box](https://sing-box.sagernet.org/).

## Features

- **Live Traffic Monitoring**: Real-time upload/download speeds and traffic totals directly in the status bar.
- **Node & Outbound Selector**: Quick selection of active proxy nodes across outbound groups with latency badges.
- **Mode Switching**: Instant switching between `Rule`, `Global`, and `Direct` routing modes.
- **URL & Password Configuration**: Configurable HTTP URL and Password/Secret via `shell.json` settings, dedicated config file (`~/.config/sing-box-dashboard/config.json`), or right from the panel UI.
- **Universal API Support**: Works with both sing-box Clash-compatible REST API (`http://127.0.0.1:9090`) and sing-box Daemon API (`http://127.0.0.1:9091`).
- **Quick Actions**:
  - Close all active connections
  - Trigger URL latency test
  - Open full web dashboard in browser

## Installation

### Method 1: Local installation

Copy or link the plugin directory to `~/.config/omarchy/plugins/sing-box-dashboard`:

```bash
mkdir -p ~/.config/omarchy/plugins/
cp -r omarchy-plugin-sing-box-dashboard ~/.config/omarchy/plugins/sing-box-dashboard
```

Enable the plugin:

```bash
omarchy plugin enable sing-box-dashboard
```

### Method 2: Add via git

```bash
omarchy plugin add <repo-url> --enable --yes
```

## Configuration

In `~/.config/omarchy/shell.json`:

```json
{
  "id": "sing-box-dashboard",
  "url": "http://127.0.0.1:9090",
  "password": "your-secret-token",
  "refreshIntervalSec": 2
}
```

Or simply click the widget in your bar to open the configuration drawer and enter the API URL and Password.

## License

MIT
