# sing-box-dashboard (Omarchy Shell Plugin)

A native [Omarchy](https://omarchy.org/) status bar widget and full-featured control panel for [sing-box](https://sing-box.sagernet.org/) (specifically optimized for sing-box 1.14+).

Built following the official [sing-box-dashboard](https://github.com/SagerNet/sing-box) design and Omarchy shell plugin standards.

## Features

- **Live Status Bar Monitoring**:
  - Real-time uplink & downlink throughput rates (`↑ 1.7 KB/s  ↓ 8.0 KB/s`).
  - Online/Offline/Unauthorized status indicator dot.
  - Hover tooltip with active routing mode, active node, and detailed traffic.
- **Overview Tab**:
  - Routing mode pills: `Rule` | `Direct` | `Global`.
  - 2x2 Metric Cards: Upload speed & total, Download speed & total, Active connections count, System memory & goroutines.
  - Active Outbound Node card with quick-switch shortcut.
  - Global URL latency test trigger.
- **Groups Tab**:
  - Multi-group selector tabs (`select`, `urltest`, etc.).
  - Group details: Type, node count, and "Test Group" button.
  - Node cards with node name, protocol type (`vless`, `hysteria2`, `tuic`, `anytls`, `vmess`), latency ms color badges (green <200ms, orange <500ms, red >500ms), and active selection checkmark (`󰄬`).
  - One-click node selection.
- **Connections Tab**:
  - Live active connections table with hostname, destination, protocol (`TCP`/`UDP`), inbound (`tun-in`), outbound proxy node, and live traffic (`↑` / `↓`).
  - Search filter input to find connections by domain, IP, or outbound.
  - Individual connection close action button (`󰅙`).
  - "Close All Connections" bulk action.
- **Logs Tab**:
  - Real-time sing-box service logs viewer.
  - Log level filter: `INFO`, `WARN`, `ERROR`, `DEBUG`, `TRACE`.
  - Monospace styled console output.
- **Settings Tab**:
  - Configure sing-box API URL (e.g. `http://127.0.0.1:9091` or `http://127.0.0.1:9090`).
  - Configure API Secret / Bearer token with show/hide password toggle.
  - "Save & Connect" with auto-persistence to `~/.config/sing-box-dashboard/config.json`.
  - "Open Web Dashboard" button to launch the official web UI in browser.
- **Universal API Integration**:
  - Supports sing-box 1.14 daemon CLI/API (`sing-box api status`, `group`, `connection`, `logs`, `mode`).
  - Supports Clash-compatible REST API endpoints.

## Installation

### Method 1: Local installation

Copy the plugin directory to `~/.config/omarchy/plugins/sing-box-dashboard`:

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
  "url": "http://127.0.0.1:9091",
  "password": "your-secret-token",
  "refreshIntervalSec": 2
}
```

Or simply click the widget in your bar to open the Settings tab and enter the API URL and Password.

## Validation

Verify that the plugin complies with Omarchy standards:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
```

## License

MIT
