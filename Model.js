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

function delayColor(delay, foreground, dim) {
  var d = Number(delay) || 0
  if (d <= 0) return dim || "#888888"
  if (d < 200) return "#4caf50" // green
  if (d < 500) return "#ff9800" // orange
  return "#f44336" // red
}

function delayText(delay) {
  var d = Number(delay) || 0
  if (d <= 0) return "--"
  return d + " ms"
}

function normalizeMode(mode) {
  var m = String(mode || "rule").toLowerCase()
  if (m === "global") return "Global"
  if (m === "direct") return "Direct"
  return "Rule"
}
