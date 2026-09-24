.pragma library

// Formatting and data helpers for sing-box-dashboard

function formatBytes(bytes) {
  var b = Number(bytes) || 0
  if (b <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = Math.floor(Math.log(b) / Math.log(1024))
  if (i < 0) i = 0
  if (i >= units.length) i = units.length - 1
  var val = b / Math.pow(1024, i)
  return (i === 0 ? val.toFixed(0) : val.toFixed(1)) + " " + units[i]
}

function formatRate(bytesPerSec) {
  var b = Number(bytesPerSec) || 0
  if (b <= 0) return "0 B/s"
  var units = ["B/s", "KB/s", "MB/s", "GB/s"]
  var i = Math.floor(Math.log(b) / Math.log(1024))
  if (i < 0) i = 0
  if (i >= units.length) i = units.length - 1
  var val = b / Math.pow(1024, i)
  return (i === 0 ? val.toFixed(0) : val.toFixed(1)) + " " + units[i]
}

var PROXY_DISPLAY_TYPES = {
  "direct": "Direct",
  "block": "Block",
  "dns": "DNS",
  "socks": "SOCKS",
  "http": "HTTP",
  "shadowsocks": "Shadowsocks",
  "vmess": "VMess",
  "trojan": "Trojan",
  "naive": "Naive",
  "wireguard": "WireGuard",
  "hysteria": "Hysteria",
  "tor": "Tor",
  "ssh": "SSH",
  "shadowtls": "ShadowTLS",
  "shadowsocksr": "ShadowsocksR",
  "vless": "VLESS",
  "tuic": "TUIC",
  "hysteria2": "Hysteria2",
  "anytls": "AnyTLS",
  "tailscale": "Tailscale",
  "selector": "Selector",
  "urltest": "URLTest",
  "snell": "Snell"
}

function proxyDisplayType(type) {
  if (!type) return "Proxy"
  var key = String(type).toLowerCase()
  return PROXY_DISPLAY_TYPES[key] || type
}

function delayColor(delay) {
  var d = Number(delay) || 0
  if (d <= 0) return "#3a3a3c"
  if (d < 800) return "#34d399" // good (green)
  if (d < 1500) return "#fb923c" // medium (orange)
  return "#ef4444" // bad (red)
}

function delayText(delay) {
  var d = Number(delay) || 0
  if (d <= 0) return ""
  return d + "ms"
}

function normalizeMode(mode) {
  var m = String(mode || "rule").toLowerCase()
  if (m === "global") return "Global"
  if (m === "direct") return "Direct"
  return "Rule"
}
