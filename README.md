# sing-box-dashboard (Omarchy Shell Plugin)

A native [Omarchy](https://omarchy.org/) status bar widget and full-featured control panel for [sing-box](https://sing-box.sagernet.org/) (specifically optimized for sing-box 1.14+).

Built following the official sing-box dashboard design language and Omarchy shell plugin standards.

<img width="873" height="808" alt="screenshot-2026-09-24_15-59-22" src="https://github.com/user-attachments/assets/adce406f-2c74-418a-93dd-9d6fe428631d" />

<img width="875" height="696" alt="screenshot-2026-09-24_16-00-27" src="https://github.com/user-attachments/assets/f139d356-04af-4b12-a994-0c60d9a50955" />

<img width="870" height="979" alt="screenshot-2026-09-24_15-59-36" src="https://github.com/user-attachments/assets/bfadb70a-6754-4760-ae9a-de22ebb58de8" />
<img width="875" height="1081" alt="screenshot-2026-09-24_16-01-41" src="https://github.com/user-attachments/assets/f9872608-98d0-498a-a34a-f8fddae74ae9" />

<img width="870" height="929" alt="screenshot-2026-09-24_16-00-12" src="https://github.com/user-attachments/assets/67f1dfc9-1ff7-46d5-aea8-dbc0e6b3fa48" />


## Features

- **Live Status Bar Monitoring**:
  - Real-time uplink & downlink throughput rates (`↑ 1.7 KB/s  ↓ 8.0 KB/s`).
  - Online/Offline/Unauthorized status indicator dot.
  - Native monochrome vector icon matching Omarchy bar theme styling.
  - Hover tooltip with active routing mode, active node, and detailed traffic.
- **Overview Tab**:
  - Routing mode selector pills: `Rule` | `Direct` | `Global`.
  - 2x2 Metric Cards: Upload speed & total, Download speed & total, Active connections count, System memory & goroutines.
  - Active Outbound Node card with quick-switch shortcut.
  - Global URL latency test trigger.
- **Groups Tab**:
  - Multi-group selector tabs (`select`, `urltest`, etc.).
  - Group details: Type, node count, and "Test Group" button.
  - Node cards with node name, protocol type (`vless`, `hysteria2`, `tuic`, `anytls`, `vmess`), latency color badges (green <200ms, orange <500ms, red >500ms), and active selection checkmark.
  - One-click node selection.
- **Connections Tab**:
  - Live active connections table with hostname, destination, protocol (`TCP`/`UDP`), inbound (`tun-in`), outbound proxy node, and live traffic (`↑` / `↓`).
  - Search filter input to find connections by domain, IP, or outbound.
  - Individual connection close action button.
  - "Close All Connections" bulk action button.
- **Logs Tab**:
  - Real-time sing-box service logs viewer with ANSI color highlighting.
  - Log level filter: `INFO`, `WARN`, `ERROR`, `DEBUG`, `TRACE`.
  - Monospace styled console output with auto-scroll and pause controls.
- **Settings Tab**:
  - Configure sing-box API URL (e.g. `http://127.0.0.1:9090` or `http://127.0.0.1:9091`).
  - Configure API Secret / Bearer token with show/hide password toggle.
  - Toggle real-time traffic throughput display in the top bar.
  - "Save & Connect" with local persistence to `~/.config/sing-box-dashboard/config.json`.
  - "Open Web Dashboard" button to launch the web UI in your browser.
- **Universal API Integration**:
  - Supports sing-box 1.14 daemon CLI/API (`sing-box api status`, `group`, `connection`, `logs`, `mode`).
  - Supports Clash-compatible REST API endpoints.

## Dependencies

- **Python 3** (uses standard library modules: `urllib`, `json`, `os`, `sys`, `socket`; no pip dependencies).
- **sing-box** (version 1.14+ recommended with experimental Clash REST API or daemon API enabled in configuration).

## Installation

### Method 1: Via Omarchy CLI (Git)

```bash
omarchy plugin add https://github.com/xi4oh4o/omarchy-plugin-sing-box-dashboard --enable --yes
```

### Method 2: Manual Local Installation

Clone or copy the directory into `~/.config/omarchy/plugins/sing-box-dashboard`:

```bash
git clone https://github.com/xi4oh4o/omarchy-plugin-sing-box-dashboard.git ~/.config/omarchy/plugins/sing-box-dashboard
omarchy plugin enable sing-box-dashboard
```

## Removal

To disable and remove the plugin:

```bash
omarchy plugin disable sing-box-dashboard
omarchy plugin remove sing-box-dashboard --yes
```

Or manually remove the installed directory:

```bash
rm -rf ~/.config/omarchy/plugins/sing-box-dashboard
```

## Configuration

Settings can be managed directly inside the panel's **Settings** tab.

Alternatively, declare overrides in `~/.config/omarchy/shell.json`:

```json
{
  "id": "sing-box-dashboard",
  "url": "http://127.0.0.1:9090",
  "password": "your-secret-token",
  "refreshIntervalSec": 2,
  "showTraffic": true
}
```

## Validation

Verify that the plugin complies with Omarchy standards:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml SingBoxIcon.qml
```

## License

[MIT](LICENSE)
