#!/usr/bin/env python3
"""
sing-box API client helper for Omarchy plugin sing-box-dashboard.
Supports both Clash-compatible REST API (e.g. port 9090) and sing-box daemon API (e.g. port 9091).
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
        "url": os.environ.get("BOX_API_URL", "http://127.0.0.1:9090"),
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
        return "http://127.0.0.1:9090"
    if not u.startswith("http://") and not u.startswith("https://"):
        return f"http://{u}"
    return u


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
        with urllib.request.urlopen(req, timeout=timeout) as resp:
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


def get_clash_status(url, secret):
    # Check version
    ver_res = http_request(url, "/version", secret, timeout=2)
    if not ver_res["ok"]:
        return {
            "online": False,
            "error": ver_res.get("error", "Failed to reach sing-box API"),
            "status": ver_res.get("status", 0),
        }

    version = ""
    if isinstance(ver_res.get("data"), dict):
        version = ver_res["data"].get("version", "")

    # Configs / mode
    mode = "rule"
    cfg_res = http_request(url, "/configs", secret, timeout=2)
    if cfg_res["ok"] and isinstance(cfg_res.get("data"), dict):
        mode = cfg_res["data"].get("mode", "rule").lower()

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
    if prox_res["ok"] and isinstance(prox_res.get("data"), dict):
        all_proxies = prox_res["data"].get("proxies", {})
        # Find selector groups
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
        "activeNode": active_node,
        "uploadRate": up_rate,
        "downloadRate": down_rate,
        "uploadTotal": upload_total,
        "downloadTotal": download_total,
        "connectionsCount": conn_count,
        "groups": groups,
    }


def get_daemon_status(url, secret):
    # Try using `sing-box api` CLI if available
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

        # Get status
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

        # Parse groups
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
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 2:
                gtag = parts[0]
                gsel = parts[1] if len(parts) > 1 else ""
                groups.append({"name": gtag, "type": "Selector", "selected": gsel, "items": []})
                if not active_node:
                    active_node = gsel

        return {
            "online": True,
            "apiType": "daemon",
            "version": version,
            "mode": "rule",
            "activeNode": active_node,
            "uploadRate": upload_rate,
            "downloadRate": download_rate,
            "uploadTotal": upload_total,
            "downloadTotal": download_total,
            "connectionsCount": conn_count,
            "groups": groups,
        }
    except Exception as e:
        return {"online": False, "error": str(e), "status": 500}


def get_status(url, secret):
    res = get_clash_status(url, secret)
    if res["online"] or res.get("status") == 401:
        return res
    # If Clash API gave 404 or connection error, check daemon API
    d_res = get_daemon_status(url, secret)
    if d_res["online"] or d_res.get("status") == 401:
        return d_res
    return res


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
    # Try daemon api CLI
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


def urltest(url, secret, node):
    res = http_request(
        url,
        f"/proxies/{urllib.parse.quote(node)}/delay?url=http://www.gstatic.com/generate_204&timeout=3000",
        secret,
    )
    if res["ok"] and isinstance(res.get("data"), dict):
        return {"success": True, "delay": res["data"].get("delay", 0)}
    # Try daemon api CLI
    try:
        proc = subprocess.run(
            ["sing-box", "api", "group", "urltest", node, "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if proc.returncode == 0:
            return {"success": True, "output": proc.stdout.strip()}
        return {"success": False, "error": proc.stderr.strip() or res.get("error")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def set_mode(url, secret, mode):
    res = http_request(url, "/configs", secret, method="PATCH", body={"mode": mode})
    if res["ok"]:
        return {"success": True, "mode": mode}
    try:
        proc = subprocess.run(
            ["sing-box", "api", "mode", mode.lower(), "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            return {"success": True, "mode": mode}
        return {"success": False, "error": proc.stderr.strip() or res.get("error")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def close_connections(url, secret):
    res = http_request(url, "/connections", secret, method="DELETE")
    if res["ok"]:
        return {"success": True}
    try:
        proc = subprocess.run(
            ["sing-box", "api", "connection", "close", "--all", "--url", url, "--secret", secret],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr.strip() or res.get("error")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def main():
    parser = argparse.ArgumentParser(description="sing-box API helper")
    parser.add_argument("--url", default="", help="sing-box API URL")
    parser.add_argument("--password", default="", help="sing-box API password/secret")
    parser.add_argument("command", choices=["status", "select", "urltest", "set-mode", "close-connections", "save-config", "get-config"])
    parser.add_argument("args", nargs="*", help="Additional arguments")

    parsed = parser.parse_args()
    cfg = load_config()

    url = parsed.url or cfg.get("url", "http://127.0.0.1:9090")
    password = parsed.password if parsed.password != "" else cfg.get("password", "")

    if parsed.command == "get-config":
        print(json.dumps(cfg))
        return

    if parsed.command == "save-config":
        new_url = parsed.args[0] if len(parsed.args) > 0 else url
        new_pass = parsed.args[1] if len(parsed.args) > 1 else password
        saved = save_config(new_url, new_pass)
        print(json.dumps({"success": True, "config": saved}))
        return

    if parsed.command == "status":
        res = get_status(url, password)
        print(json.dumps(res))
    elif parsed.command == "select":
        if len(parsed.args) < 2:
            print(json.dumps({"success": False, "error": "Usage: select <group> <node>"}))
            sys.exit(1)
        res = select_outbound(url, password, parsed.args[0], parsed.args[1])
        print(json.dumps(res))
    elif parsed.command == "urltest":
        node = parsed.args[0] if parsed.args else ""
        res = urltest(url, password, node)
        print(json.dumps(res))
    elif parsed.command == "set-mode":
        if not parsed.args:
            print(json.dumps({"success": False, "error": "Usage: set-mode <rule|global|direct>"}))
            sys.exit(1)
        res = set_mode(url, password, parsed.args[0])
        print(json.dumps(res))
    elif parsed.command == "close-connections":
        res = close_connections(url, password)
        print(json.dumps(res))


if __name__ == "__main__":
    main()
