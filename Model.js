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

// Log formatting matching official sing-box-dashboard
var CLIENT_COLORS = {
  "30": "#000000",
  "31": "#ff2159", // red
  "32": "#2ecc70", // green
  "33": "#e6e600", // yellow
  "34": "#3399db", // blue
  "35": "#9c59b5", // purple
  "36": "#5cade3", // cyan
  "37": "#edf0f2"  // white
}

var CONN_PALETTE = [
  "#ff2159", // 31 Red
  "#2ecc70", // 32 Green
  "#e6e600", // 33 Yellow
  "#3399db", // 34 Blue
  "#9c59b5", // 35 Purple
  "#5cade3"  // 36 Cyan
]

function xterm256(n) {
  if (n < 8) return CLIENT_COLORS[String(30 + n)] || "#edf0f2"
  if (n < 16) {
    var bright = ["#686868", "#ff5f87", "#5af78e", "#f3f99d", "#57c7ff", "#ff6ac1", "#9aedfe", "#ffffff"]
    return bright[n - 8]
  }
  if (n < 232) {
    n -= 16
    var steps = [0, 95, 135, 175, 215, 255]
    var r = steps[Math.floor(n / 36)]
    var g = steps[Math.floor((n % 36) / 6)]
    var b = steps[n % 6]
    return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)
  }
  var gr = 8 + (n - 232) * 10
  return "#" + ((1 << 24) + (gr << 16) + (gr << 8) + gr).toString(16).slice(1)
}

function connectionIdColor(cid) {
  var n = Number(cid)
  if (!isNaN(n) && n > 0) {
    return CONN_PALETTE[n % 6]
  }
  var hash = 0
  var s = String(cid || "")
  for (var i = 0; i < s.length; i++) {
    hash = ((hash << 5) - hash) + s.charCodeAt(i)
    hash |= 0
  }
  return CONN_PALETTE[Math.abs(hash) % 6]
}

function logLevelColor(level) {
  var l = String(level || "INFO").toUpperCase()
  if (l === "ERROR" || l === "FATAL") return "#ff2159"
  if (l === "WARN") return "#e6e600"
  if (l === "DEBUG") return "#9c59b5"
  if (l === "TRACE") return "#686868"
  return "#5cade3"
}

function escapeHtml(str) {
  if (!str) return ""
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function ansiToHtml(text) {
  if (!text) return ""
  var pattern = /\x1b\[([0-9;]*)m/g
  var parts = []
  var cursor = 0
  var match
  var fontOpen = false

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > cursor) {
      parts.push(escapeHtml(text.slice(cursor, match.index)))
    }
    cursor = pattern.lastIndex
    var code = match[1] || "0"

    if (code === "0" || code === "") {
      if (fontOpen) {
        parts.push("</font>")
        fontOpen = false
      }
    } else if (CLIENT_COLORS[code]) {
      if (fontOpen) parts.push("</font>")
      parts.push("<font color=\"" + CLIENT_COLORS[code] + "\">")
      fontOpen = true
    } else if (code.indexOf("38;5;") === 0) {
      var colNum = parseInt(code.split(";")[2], 10)
      var hex = xterm256(colNum)
      if (fontOpen) parts.push("</font>")
      parts.push("<font color=\"" + hex + "\">")
      fontOpen = true
    }
  }

  if (cursor < text.length) {
    parts.push(escapeHtml(text.slice(cursor)))
  }
  if (fontOpen) {
    parts.push("</font>")
  }

  return "<font color=\"#edf0f2\">" + parts.join("") + "</font>"
}

function formatLogLineHtml(logItem) {
  if (!logItem) return ""
  var raw = logItem.raw ? String(logItem.raw) : ""
  if (raw && raw.indexOf("\x1b[") !== -1) {
    return ansiToHtml(raw)
  }

  var lvl = String(logItem.level || "INFO").toUpperCase()
  var lvlCol = logLevelColor(lvl)
  var seq = logItem.seq ? String(logItem.seq) : ""
  var msg = String(logItem.message || "")

  var html = "<font color='" + lvlCol + "'>" + escapeHtml(lvl) + "</font>"

  if (seq) {
    html += "<font color='#edf0f2'>[" + escapeHtml(seq) + "]</font> "
  } else {
    html += " "
  }

  var match = msg.match(/^\[([0-9]+)(?:\s+([^\]]+))?\]\s*(.*)$/)
  if (match) {
    var cid = match[1]
    var elapsed = match[2]
    var rest = match[3]
    var cidCol = connectionIdColor(cid)

    html += "<font color='#edf0f2'>[</font>" +
            "<font color='" + cidCol + "'>" + escapeHtml(cid) + "</font>"
    if (elapsed) {
      html += "<font color='#edf0f2'> " + escapeHtml(elapsed) + "</font>"
    }
    html += "<font color='#edf0f2'>] </font>" +
            "<font color='#edf0f2'>" + escapeHtml(rest) + "</font>"
  } else {
    html += "<font color='#edf0f2'>" + escapeHtml(msg) + "</font>"
  }

  return html
}


