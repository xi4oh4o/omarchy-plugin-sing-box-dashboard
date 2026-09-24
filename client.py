#!/usr/bin/env python3
"""
sing-box 1.14 API client helper for Omarchy plugin sing-box-dashboard.
Supports:
  - sing-box daemon API (e.g. port 9091, via 'sing-box api')
  - Clash-compatible REST API (e.g. port 9090, via HTTP)
  - Full dashboard functions: Status/Overview, Groups, Connections, Logs, Mode, URLTest
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_DIR = os.path.expanduser("~/.config/sing-box-dashboard")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
CACHE_FILE = os.path.join(CONFIG_DIR, "state_cache.json")


def load_config():
    cfg = {
        "url": os.environ.get("BOX_API_URL", "http://127.0.0.1:9091"),
        "password": os.environ.get("BOX_API_SECRET", ""),
    }
    if os.path.isfile(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                if isinstance(saved, dict):
                    if "url" in saved and saved["url"]:
                        cfg["url"] = saved["url"]
                    if "password" in saved:
                        cfg["password"] = saved["password"]
        except Exception:
            pass
    return cfg


def save_config(url, password):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    cfg = {"url": url, "password": password}
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    return cfg


def load_cache():
    if os.path.isfile(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_cache(cache_data):
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache_data, f)
    except Exception:
        pass


def normalize_url(url):
    u = (url or "").strip().rstrip("/")
    if not u:
        return "http://127.0.0.1:9091"
    if not u.startswith("http://") and not u.startswith("https://"):
        return f"http://{u}"
    return u


def parse_bytes_unit(val_str, unit_str):
    try:
        val = float(val_str)
        u = (unit_str or "").strip().upper()
        if "T" in u:
            return int(val * 1024 * 1024 * 1024 * 1024)
        elif "G" in u:
            return int(val * 1024 * 1024 * 1024)
        elif "M" in u:
            return int(val * 1024 * 1024)
        elif "K" in u:
            return int(val * 1024)
        return int(val)
    except Exception:
        return 0


def format_bytes_val(b):
    try:
        val = float(b)
        if val <= 0:
            return "0 B"
        for unit in ["B", "KB", "MB", "GB", "TB"]:
            if val < 1024 or unit == "TB":
                return f"{val:.1f} {unit}".replace(".0 ", " ")
            val /= 1024
        return f"{val:.1f} TB"
    except Exception:
        return "0 B"


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

_opener = urllib.request.build_opener(NoRedirectHandler)


def http_request(url, path, secret, method="GET", body=None, timeout=3):
    full_url = f"{normalize_url(url)}/{path.lstrip('/')}"
    headers = {"Accept": "application/json"}
    if secret:
        headers["Authorization"] = f"Bearer {secret}"

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(full_url, data=data, headers=headers, method=method)
    try:
        with _opener.open(req, timeout=timeout) as resp:
            content_type = resp.headers.get("Content-Type", "")
            raw = resp.read().decode("utf-8", errors="replace")
            if "application/json" in content_type or raw.startswith("{") or raw.startswith("["):
                try:
                    return {"ok": True, "status": resp.status, "data": json.loads(raw)}
                except Exception:
                    pass
            return {"ok": True, "status": resp.status, "data": raw}
    except urllib.error.HTTPError as e:
        err_msg = ""
        try:
            err_raw = e.read().decode("utf-8", errors="replace")
            err_json = json.loads(err_raw)
            err_msg = err_json.get("message", err_raw)
        except Exception:
            err_msg = str(e)
        return {"ok": False, "status": e.code, "error": err_msg or str(e)}
    except Exception as e:
        return {"ok": False, "status": 0, "error": str(e)}


# -------------------------------------------------------------
# Clash REST API Adapter
# -------------------------------------------------------------

def get_clash_status(url, secret):
    ver_res = http_request(url, "/version", secret, timeout=2)
    # Must be valid json object containing "version"
    if not ver_res["ok"] or not isinstance(ver_res.get("data"), dict) or "version" not in ver_res["data"]:
        return {
            "online": False,
            "error": ver_res.get("error", "Not a Clash REST API"),
            "status": ver_res.get("status", 0),
        }

    version = ver_res["data"].get("version", "")

    # Configs / mode
    mode = "Rule"
    mode_list = ["Rule", "Global", "Direct"]
    cfg_res = http_request(url, "/configs", secret, timeout=2)
    if cfg_res["ok"] and isinstance(cfg_res.get("data"), dict):
        raw_mode = cfg_res["data"].get("mode", "Rule")
        mode = raw_mode.capitalize() if raw_mode else "Rule"

    # Connections & traffic totals
    conn_res = http_request(url, "/connections", secret, timeout=2)
    upload_total = 0
    download_total = 0
    conn_count = 0
    if conn_res["ok"] and isinstance(conn_res.get("data"), dict):
        upload_total = conn_res["data"].get("uploadTotal", 0)
        download_total = conn_res["data"].get("downloadTotal", 0)
        conn_count = len(conn_res["data"].get("connections", []))

    # Calculate upload/download rates from cache
    cache = load_cache()
    now_ts = time.time()
    last_ts = cache.get("ts", now_ts)
    last_up = cache.get("up", upload_total)
    last_down = cache.get("down", download_total)
    dt = max(now_ts - last_ts, 0.5)

    up_rate = max(0, int((upload_total - last_up) / dt)) if upload_total >= last_up else 0
    down_rate = max(0, int((download_total - last_down) / dt)) if download_total >= last_down else 0

    save_cache({"ts": now_ts, "up": upload_total, "down": download_total})

    # Proxies / Groups
    groups = []
    active_node = ""
    prox_res = http_request(url, "/proxies", secret, timeout=2)
    if prox_res["ok"] and isinstance(prox_res.get("data"), dict) and "proxies" in prox_res["data"]:
        all_proxies = prox_res["data"].get("proxies", {})
        for name, p in all_proxies.items():
            ptype = p.get("type", "")
            if ptype in ("Selector", "URLTest", "Fallback", "LoadBalance"):
                selected = p.get("now", "")
                items = []
                for item_name in p.get("all", []):
                    item_info = all_proxies.get(item_name, {})
                    history = item_info.get("history", [])
                    delay = history[-1].get("delay", 0) if history else 0
                    items.append({
                        "name": item_name,
                        "type": item_info.get("type", "Proxy"),
                        "delay": delay,
                    })
                groups.append({
                    "name": name,
                    "type": ptype,
                    "selected": selected,
                    "items": items,
                })
                if not active_node and selected:
                    active_node = selected

    return {
        "online": True,
        "apiType": "clash",
        "version": version,
        "mode": mode,
        "modeList": mode_list,
        "activeNode": active_node,
        "uptime": "",
        "uploadRate": up_rate,
        "downloadRate": down_rate,
        "uploadTotal": upload_total,
        "downloadTotal": download_total,
        "connectionsCount": conn_count,
        "connectionsIn": conn_count,
        "connectionsOut": conn_count,
        "memory": 0,
        "goroutines": 0,
        "groups": groups,
    }


# -------------------------------------------------------------
# sing-box 1.14 Daemon CLI Adapter
# -------------------------------------------------------------

def get_daemon_status(url, secret):
    try:
        proc = subprocess.run(
            ["sing-box", "api", "version", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode != 0:
            err = proc.stderr.strip() or proc.stdout.strip()
            return {"online": False, "error": err, "status": 401 if "authorization" in err.lower() else 500}
        version = proc.stdout.strip()

        # Status output
        status_proc = subprocess.run(
            ["sing-box", "api", "status", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        stat_out = status_proc.stdout

        upload_rate = 0
        download_rate = 0
        upload_total = 0
        download_total = 0
        conn_count = 0
        memory_bytes = 0
        goroutines = 0

        # Uptime: 1h32m11s
        uptime = ""
        upt_m = re.search(r"Uptime:\s*(\S+)", stat_out)
        if upt_m:
            uptime = upt_m.group(1)

        # Memory: 133 MB
        mem_m = re.search(r"Memory:\s*([0-9.]+)\s*([A-Za-z]+)", stat_out)
        if mem_m:
            memory_bytes = parse_bytes_unit(mem_m.group(1), mem_m.group(2))

        # Goroutines: 196
        gor_m = re.search(r"Goroutines:\s*([0-9]+)", stat_out)
        if gor_m:
            goroutines = int(gor_m.group(1))

        # Connections: 19 in / 29 out
        conn_in = 0
        conn_out = 0
        conn_m = re.search(r"Connections:\s*([0-9]+)\s*in\s*/\s*([0-9]+)\s*out", stat_out)
        if conn_m:
            conn_in = int(conn_m.group(1))
            conn_out = int(conn_m.group(2))
            conn_count = conn_out
        else:
            conn_single = re.search(r"Connections(?:\s*Out)?:\s*([0-9]+)", stat_out)
            if conn_single:
                conn_count = int(conn_single.group(1))
                conn_out = conn_count

        # Uplink: 1.7 kB/s (127 MB total)
        up_m = re.search(r"Uplink:\s*([0-9.]+)\s*([A-Za-z/]+)(?:\s*\(([0-9.]+)\s*([A-Za-z]+)\s*total\))?", stat_out)
        if up_m:
            upload_rate = parse_bytes_unit(up_m.group(1), up_m.group(2).replace("/s", ""))
            if up_m.group(3) and up_m.group(4):
                upload_total = parse_bytes_unit(up_m.group(3), up_m.group(4))

        # Downlink: 8.0 kB/s (1.4 GB total)
        down_m = re.search(r"Downlink:\s*([0-9.]+)\s*([A-Za-z/]+)(?:\s*\(([0-9.]+)\s*([A-Za-z]+)\s*total\))?", stat_out)
        if down_m:
            download_rate = parse_bytes_unit(down_m.group(1), down_m.group(2).replace("/s", ""))
            if down_m.group(3) and down_m.group(4):
                download_total = parse_bytes_unit(down_m.group(3), down_m.group(4))

        # Mode
        mode = "Rule"
        mode_proc = subprocess.run(
            ["sing-box", "api", "mode", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if mode_proc.returncode == 0 and mode_proc.stdout.strip():
            mode = mode_proc.stdout.strip().capitalize()

        mode_list = ["Rule", "Global", "Direct"]
        mlist_proc = subprocess.run(
            ["sing-box", "api", "mode", "list", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if mlist_proc.returncode == 0 and mlist_proc.stdout.strip():
            lines = [l.strip().capitalize() for l in mlist_proc.stdout.splitlines() if l.strip()]
            if lines:
                mode_list = lines

        # Groups
        grp_proc = subprocess.run(
            ["sing-box", "api", "group", "list", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        groups = []
        active_node = ""
        for line in grp_proc.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("TAG"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                gtag = parts[0]
                gtype = parts[1].capitalize()
                gsel = parts[2] if len(parts) > 2 else ""

                # Show items for group
                items = []
                show_proc = subprocess.run(
                    ["sing-box", "api", "group", "show", gtag, "--url", url, "--secret", secret],
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
                if show_proc.returncode == 0:
                    for sline in show_proc.stdout.splitlines():
                        sline = sline.strip()
                        if not sline or sline.startswith("Tag:") or sline.startswith("Type:") or sline.startswith("Selected:") or sline.startswith("TAG"):
                            continue
                        sparts = sline.split()
                        if len(sparts) >= 2:
                            itag = sparts[0]
                            itype = sparts[1]
                            delay = 0
                            dm = re.search(r"([0-9]+)\s*ms", sline)
                            if dm:
                                delay = int(dm.group(1))
                            items.append({"name": itag, "type": itype, "delay": delay})

                groups.append({"name": gtag, "type": gtype, "selected": gsel, "items": items})
                if not active_node and gsel:
                    active_node = gsel

        return {
            "online": True,
            "apiType": "daemon",
            "version": version,
            "mode": mode,
            "modeList": mode_list,
            "activeNode": active_node,
            "uptime": uptime,
            "uploadRate": upload_rate,
            "downloadRate": download_rate,
            "uploadTotal": upload_total,
            "downloadTotal": download_total,
            "connectionsCount": conn_count,
            "connectionsIn": conn_in,
            "connectionsOut": conn_out,
            "memory": memory_bytes,
            "goroutines": goroutines,
            "groups": groups,
        }
    except Exception as e:
        return {"online": False, "error": str(e), "status": 500}


def get_status(url, secret):
    # Try Clash REST first
    clash_res = get_clash_status(url, secret)
    if clash_res["online"]:
        return clash_res
    if clash_res.get("status") == 401:
        return clash_res

    # Try daemon API
    daemon_res = get_daemon_status(url, secret)
    if daemon_res["online"] or daemon_res.get("status") == 401:
        return daemon_res

    return clash_res if clash_res.get("status") != 0 else daemon_res


# -------------------------------------------------------------
# Groups / Proxies
# -------------------------------------------------------------

def get_groups(url, secret):
    # Try Clash API
    prox_res = http_request(url, "/proxies", secret, timeout=3)
    if prox_res["ok"] and isinstance(prox_res.get("data"), dict) and "proxies" in prox_res["data"]:
        all_proxies = prox_res["data"].get("proxies", {})
        groups = []
        for name, p in all_proxies.items():
            ptype = p.get("type", "")
            if ptype in ("Selector", "URLTest", "Fallback", "LoadBalance"):
                selected = p.get("now", "")
                items = []
                for item_name in p.get("all", []):
                    item_info = all_proxies.get(item_name, {})
                    history = item_info.get("history", [])
                    delay = history[-1].get("delay", 0) if history else 0
                    items.append({
                        "name": item_name,
                        "type": item_info.get("type", "Proxy"),
                        "delay": delay,
                    })
                groups.append({
                    "name": name,
                    "type": ptype,
                    "selected": selected,
                    "items": items,
                })
        return {"online": True, "groups": groups}

    # Fallback to daemon CLI
    try:
        grp_proc = subprocess.run(
            ["sing-box", "api", "group", "list", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if grp_proc.returncode != 0:
            return {"online": False, "error": grp_proc.stderr.strip() or "Failed to list groups"}
        groups = []
        for line in grp_proc.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("TAG"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                gtag = parts[0]
                gtype = parts[1].capitalize()
                gsel = parts[2] if len(parts) > 2 else ""
                items = []
                show_proc = subprocess.run(
                    ["sing-box", "api", "group", "show", gtag, "--url", url, "--secret", secret],
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
                if show_proc.returncode == 0:
                    for sline in show_proc.stdout.splitlines():
                        sline = sline.strip()
                        if not sline or sline.startswith("Tag:") or sline.startswith("Type:") or sline.startswith("Selected:") or sline.startswith("TAG"):
                            continue
                        sparts = sline.split()
                        if len(sparts) >= 2:
                            itag = sparts[0]
                            itype = sparts[1]
                            delay = 0
                            dm = re.search(r"([0-9]+)\s*ms", sline)
                            if dm:
                                delay = int(dm.group(1))
                            items.append({"name": itag, "type": itype, "delay": delay})
                groups.append({"name": gtag, "type": gtype, "selected": gsel, "items": items})
        return {"online": True, "groups": groups}
    except Exception as e:
        return {"online": False, "error": str(e)}


# -------------------------------------------------------------
# Connections
# -------------------------------------------------------------

def get_connections(url, secret):
    # Try Clash API
    res = http_request(url, "/connections", secret, timeout=2)
    if res["ok"] and isinstance(res.get("data"), dict) and "connections" in res["data"]:
        raw_conns = res["data"].get("connections", [])
        conn_list = []
        for c in raw_conns[:150]:
            meta = c.get("metadata", {})
            host = meta.get("host") or meta.get("destinationIP", "")
            port = meta.get("destinationPort", "")
            dest = f"{host}:{port}" if port and str(port) not in host else host
            network = meta.get("network", "tcp").upper()
            rule = c.get("rule", "")
            chains = c.get("chains", [])
            outbound = chains[0] if chains else ""
            inbound = meta.get("type", "inbound")
            inbound_name = meta.get("inbound", "")
            in_label = f"{inbound}/{inbound_name}" if inbound_name and inbound != inbound_name else inbound

            conn_list.append({
                "id": c.get("id", ""),
                "host": host,
                "destination": dest,
                "network": network,
                "status": "Active",
                "inbound": in_label,
                "outbound": outbound,
                "chain": " / ".join(chains) if chains else outbound,
                "route": outbound or "direct",
                "rule": rule,
                "upRate": f"↑ {format_bytes_val(c.get('curUploadRate', 0))}/s",
                "downRate": f"↓ {format_bytes_val(c.get('curDownloadRate', 0))}/s",
                "upTotal": f"↑ {format_bytes_val(c.get('upload', 0))}",
                "downTotal": f"↓ {format_bytes_val(c.get('download', 0))}",
                "upload": c.get("upload", 0),
                "download": c.get("download", 0),
            })
        return {
            "online": True,
            "connections": conn_list,
            "totalCount": len(raw_conns),
        }

    # Fallback to sing-box 1.14 daemon CLI
    try:
        cmd = [
            "sing-box", "api", "connection", "list",
            "--columns", "id,network,destination,inbound,outbound,chain,rule,rate,total",
            "--url", url,
            "--secret", secret
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if proc.returncode != 0:
            return {"online": False, "error": proc.stderr.strip() or "Failed to list connections"}
        conn_list = []
        for line in proc.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("ID"):
                continue
            parts = line.split("\t")
            if len(parts) >= 9:
                cid, cnet, cdest, cin, cout, cchain, crule, crate, ctot = parts[:9]
                chost = cdest.split(":")[0] if ":" in cdest else cdest

                # Format upload and download totals
                up_total = "↑ 0 B"
                down_total = "↓ 0 B"
                tot_m = re.search(r"↑([0-9.]+)\s*([A-Za-z]+)\s*↓([0-9.]+)\s*([A-Za-z]+)", ctot)
                if tot_m:
                    up_total = f"↑ {tot_m.group(1)} {tot_m.group(2).upper()}"
                    down_total = f"↓ {tot_m.group(3)} {tot_m.group(4).upper()}"

                # Format upload and download rates
                up_rate = "↑ 0 B/s"
                down_rate = "↓ 0 B/s"
                if crate and crate != "-":
                    rate_m = re.search(r"↑([0-9.]+)\s*([A-Za-z/]+)\s*↓([0-9.]+)\s*([A-Za-z/]+)", crate)
                    if rate_m:
                        up_rate = f"↑ {rate_m.group(1)} {rate_m.group(2)}"
                        down_rate = f"↓ {rate_m.group(3)} {rate_m.group(4)}"

                # Route group (e.g. "select" from "select/Reality-Dallas")
                route_name = cchain.split("/")[0] if ("/" in cchain and cchain != "-") else (cout if cout != "-" else cin)

                conn_list.append({
                    "id": cid,
                    "host": chost,
                    "destination": cdest,
                    "network": cnet.upper(),
                    "status": "Active",
                    "inbound": cin,
                    "outbound": cout,
                    "chain": cchain,
                    "route": route_name,
                    "rule": "" if crule == "-" else crule,
                    "upRate": up_rate,
                    "downRate": down_rate,
                    "upTotal": up_total,
                    "downTotal": down_total,
                })
        return {"online": True, "connections": conn_list[:150], "totalCount": len(conn_list)}
    except Exception as e:
        return {"online": False, "error": str(e)}


# -------------------------------------------------------------
# Logs
# -------------------------------------------------------------

def get_logs(url, secret, level="info", search=""):
    ansi_strip_re = re.compile(r"\x1b\[[0-9;]*m")
    try:
        cmd = ["sing-box", "api", "logs", "--url", url, "--secret", secret]
        if level:
            cmd.extend(["--level", level])
        if search:
            cmd.extend(["--search", search])

        output = ""
        # Try running in a pseudo-terminal to capture sing-box native ANSI color sequences
        try:
            import pty, os, select
            master, slave = pty.openpty()
            proc = subprocess.Popen(
                cmd,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
            )
            os.close(slave)
            raw_output = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                try:
                    chunk = os.read(master, 16384)
                    if not chunk:
                        break
                    raw_output += chunk
                except OSError:
                    break
            os.close(master)
            proc.terminate()
            try:
                proc.wait(timeout=0.2)
            except Exception:
                pass
            output = raw_output.decode("utf-8", errors="replace")
        except Exception:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            if proc.returncode == 0:
                output = proc.stdout

        if output:
            entries = []
            for line in output.splitlines()[-300:]:
                line = line.strip()
                if not line:
                    continue
                plain = ansi_strip_re.sub("", line)
                # Line format: INFO[14023] [1515020702 0ms] dns: cached ...
                m = re.match(r"^([A-Z]+)\[([0-9]+)\]\s*(.*)$", plain)
                if m:
                    entries.append({
                        "level": m.group(1).lower(),
                        "seq": m.group(2),
                        "message": m.group(3),
                        "raw": line,
                    })
                else:
                    lvl = "info"
                    if "ERROR" in plain or "[Error]" in plain:
                        lvl = "error"
                    elif "WARN" in plain or "[Warn]" in plain:
                        lvl = "warn"
                    elif "DEBUG" in plain or "[Debug]" in plain:
                        lvl = "debug"
                    elif "TRACE" in plain or "[Trace]" in plain:
                        lvl = "trace"
                    entries.append({
                        "level": lvl,
                        "seq": "",
                        "message": plain,
                        "raw": line,
                    })
            return {"online": True, "logs": entries}
    except Exception:
        pass

    return {"online": True, "logs": []}


# -------------------------------------------------------------
# Actions
# -------------------------------------------------------------

def select_outbound(url, secret, group, node):
    res = http_request(
        url,
        f"/proxies/{urllib.parse.quote(group)}",
        secret,
        method="PUT",
        body={"name": node},
    )
    if res["ok"]:
        return {"success": True}
    try:
        proc = subprocess.run(
            ["sing-box", "api", "group", "select", group, node, "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr.strip() or res.get("error")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def urltest(url, secret, target=""):
    if target:
        res = http_request(
            url,
            f"/proxies/{urllib.parse.quote(target)}/delay?url=http://www.gstatic.com/generate_204&timeout=3000",
            secret,
        )
        if res["ok"] and isinstance(res.get("data"), dict):
            return {"success": True, "delay": res["data"].get("delay", 0)}
    try:
        # If target specified, test group
        if target:
            proc = subprocess.run(
                ["sing-box", "api", "group", "urltest", target, "--url", url, "--secret", secret],
                capture_output=True,
                text=True,
                timeout=6,
            )
            if proc.returncode == 0:
                return {"success": True, "output": proc.stdout.strip()}
            return {"success": False, "error": proc.stderr.strip()}

        # If no target specified, test all groups
        g_res = get_groups(url, secret)
        if g_res.get("online") and g_res.get("groups"):
            for g in g_res["groups"]:
                subprocess.run(
                    ["sing-box", "api", "group", "urltest", g["name"], "--url", url, "--secret", secret],
                    capture_output=True,
                    text=True,
                    timeout=4,
                )
            return {"success": True}
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}


def set_mode(url, secret, mode):
    res = http_request(url, "/configs", secret, method="PATCH", body={"mode": mode})
    if res["ok"]:
        return {"success": True, "mode": mode}
    try:
        proc = subprocess.run(
            ["sing-box", "api", "mode", "set", mode.lower(), "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            return {"success": True, "mode": mode}
        return {"success": False, "error": proc.stderr.strip() or res.get("error")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def close_connection(url, secret, conn_id):
    try:
        proc = subprocess.run(
            ["sing-box", "api", "connection", "close", conn_id, "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=4,
        )
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr.strip()}
    except Exception as e:
        return {"success": False, "error": str(e)}


def close_connections(url, secret):
    try:
        proc = subprocess.run(
            ["sing-box", "api", "connection", "close", "--all", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=4,
        )
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr.strip()}
    except Exception as e:
        return {"success": False, "error": str(e)}


def main():
    parser = argparse.ArgumentParser(description="sing-box API helper")
    parser.add_argument("--url", default="", help="sing-box API URL")
    parser.add_argument("--password", default="", help="sing-box API password/secret")
    parser.add_argument("command", choices=[
        "status", "groups", "connections", "logs", "select", "urltest",
        "set-mode", "close-connection", "close-connections", "save-config", "get-config"
    ])
    parser.add_argument("args", nargs="*", help="Additional arguments")

    parsed = parser.parse_args()

    cfg = load_config()
    url = parsed.url or cfg["url"]
    password = parsed.password if parsed.password != "" else cfg["password"]

    if parsed.command == "get-config":
        print(json.dumps(load_config()))
        return

    if parsed.command == "save-config":
        new_url = parsed.args[0] if len(parsed.args) > 0 else url
        new_pass = parsed.args[1] if len(parsed.args) > 1 else password
        saved = save_config(new_url, new_pass)
        print(json.dumps(saved))
        return

    if parsed.command == "status":
        print(json.dumps(get_status(url, password)))
    elif parsed.command == "groups":
        print(json.dumps(get_groups(url, password)))
    elif parsed.command == "connections":
        print(json.dumps(get_connections(url, password)))
    elif parsed.command == "logs":
        lvl = parsed.args[0] if len(parsed.args) > 0 else "info"
        search = parsed.args[1] if len(parsed.args) > 1 else ""
        print(json.dumps(get_logs(url, password, lvl, search)))
    elif parsed.command == "select":
        if len(parsed.args) < 2:
            print(json.dumps({"success": False, "error": "Usage: select <group> <node>"}))
            sys.exit(1)
        print(json.dumps(select_outbound(url, password, parsed.args[0], parsed.args[1])))
    elif parsed.command == "urltest":
        target = parsed.args[0] if parsed.args else ""
        print(json.dumps(urltest(url, password, target)))
    elif parsed.command == "set-mode":
        if not parsed.args:
            print(json.dumps({"success": False, "error": "Usage: set-mode <rule|global|direct>"}))
            sys.exit(1)
        print(json.dumps(set_mode(url, password, parsed.args[0])))
    elif parsed.command == "close-connection":
        if not parsed.args:
            print(json.dumps({"success": False, "error": "Usage: close-connection <id>"}))
            sys.exit(1)
        print(json.dumps(close_connection(url, password, parsed.args[0])))
    elif parsed.command == "close-connections":
        print(json.dumps(close_connections(url, password)))


if __name__ == "__main__":
    main()
