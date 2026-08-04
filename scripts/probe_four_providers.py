#!/usr/bin/env python3
"""One-shot local quota probe for the 4 providers this SmartQuota / 智额 build keeps.

Mirrors the live endpoints used by the Swift probes so we can verify data
without building the macOS app (Xcode is not currently selected on this machine).
"""
from __future__ import annotations

import json
import re
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

CST = timezone(timedelta(hours=8))
HOME = Path.home()


def mask(s: str) -> str:
    return s[:6] + "…" + s[-4:] if len(s) > 12 else "***"


def fmt_ms(ms: int | None) -> str:
    if not ms:
        return "-"
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).astimezone(CST).strftime("%m-%d %H:%M")


def fmt_iso(s: str | None) -> str:
    if not s:
        return "-"
    try:
        # handle fractional seconds
        if s.endswith("Z"):
            s2 = s.replace("Z", "+00:00")
        else:
            s2 = s
        dt = datetime.fromisoformat(s2)
        return dt.astimezone(CST).strftime("%m-%d %H:%M")
    except Exception:
        return s[:16]


def fmt_epoch(sec: int | None) -> str:
    if not sec:
        return "-"
    return datetime.fromtimestamp(sec, tz=timezone.utc).astimezone(CST).strftime("%m-%d %H:%M")


def http_json(url: str, headers: dict, method: str = "GET", body: bytes | None = None) -> dict:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


def load_codex():
    auth = json.loads((HOME / ".codex/auth.json").read_text())
    tok = auth["tokens"]["access_token"]
    acc = auth["tokens"].get("account_id", "")
    d = http_json(
        "https://chatgpt.com/backend-api/wham/usage",
        {
            "Authorization": f"Bearer {tok}",
            "chatgpt-account-id": acc,
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0",
        },
    )
    rl = d.get("rate_limit") or {}
    primary = rl.get("primary_window") or {}
    secondary = rl.get("secondary_window")
    credits = d.get("credits") or {}
    rows = []
    if primary:
        used = primary.get("used_percent", 0)
        rows.append(("Session/Window", f"{100 - used:.0f}% left", f"used {used}%", fmt_epoch(primary.get("reset_at"))))
    if secondary:
        used = secondary.get("used_percent", 0)
        rows.append(("Weekly", f"{100 - used:.0f}% left", f"used {used}%", fmt_epoch(secondary.get("reset_at"))))
    if credits:
        rows.append(("Credits", str(credits.get("balance", "-")), "balance", "-"))
    return d.get("plan_type", "codex"), rows


def load_grok():
    auth = json.loads((HOME / ".grok/auth.json").read_text())
    entry = next(iter(auth.values()))
    tok = entry["key"]
    d = http_json(
        "https://cli-chat-proxy.grok.com/v1/billing?format=credits",
        {
            "Authorization": f"Bearer {tok}",
            "Accept": "application/json",
            "x-grok-client-version": "1.0.0",
            "User-Agent": "grok-cli",
        },
    )
    cfg = d.get("config") or {}
    period = cfg.get("currentPeriod") or {}
    used = cfg.get("creditUsagePercent", 0)
    rows = [("Weekly credits", f"{100 - used:.0f}% left", f"used {used}%", fmt_iso(period.get("end")))]
    for p in cfg.get("productUsage") or []:
        if "usagePercent" in p:
            rows.append((p.get("product", "product"), f"{100 - p['usagePercent']:.0f}% left", f"used {p['usagePercent']}%", "-"))
    return "grok", rows


def load_kimi():
    cfg_path = HOME / "Library/Application Support/kimi-desktop/daimon-share/daimon/config.json"
    cfg = json.loads(cfg_path.read_text())
    key = cfg["credentials"]["kimiCode"]["apiKey"]
    d = http_json(
        "https://api.kimi.com/coding/v1/usages",
        {
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "User-Agent": "Desktop Kimi Work",
        },
    )
    rows = []
    usage = d.get("usage") or {}
    if usage:
        rem = float(usage.get("remaining") or 0)
        lim = float(usage.get("limit") or 100) or 100
        rows.append(("Weekly", f"{rem / lim * 100:.0f}% left", f"{usage.get('remaining')}/{usage.get('limit')}", fmt_iso(usage.get("resetTime"))))
    for lim in d.get("limits") or []:
        win = lim.get("window") or {}
        detail = lim.get("detail") or {}
        rem = float(detail.get("remaining") or 0)
        total = float(detail.get("limit") or 100) or 100
        label = "5H" if win.get("duration") == 300 else "Window"
        rows.append((label, f"{rem / total * 100:.0f}% left", f"{detail.get('remaining')}/{detail.get('limit')}", fmt_iso(detail.get("resetTime"))))
    total = d.get("totalQuota") or {}
    if not total.get("limit"):
        # Monthly totalQuota is on agent-gw for Desktop / FEATURE_WORK
        try:
            d2 = http_json(
                "https://agent-gw.kimi.com/coding/v1/usages",
                {
                    "Authorization": f"Bearer {key}",
                    "Accept": "application/json",
                    "User-Agent": "Desktop Kimi Work",
                },
            )
            total = d2.get("totalQuota") or {}
        except Exception:
            total = {}
    if total.get("limit"):
        rem = float(total.get("remaining") or 0)
        lim = float(total.get("limit") or 100) or 100
        rows.append(("Monthly", f"{rem / lim * 100:.0f}% left", f"{total.get('used')}/{total.get('limit')}", fmt_iso(total.get("resetTime"))))
    level = ((d.get("user") or {}).get("membership") or {}).get("level", "kimi")
    return level, rows


def load_minimax():
    text = (HOME / ".minimax/config.yaml").read_text()
    keys = re.findall(r"apiKey:\s*(sk-cp-[A-Za-z0-9_\-]+)", text)
    if not keys:
        raise RuntimeError("no sk-cp key in ~/.minimax/config.yaml")
    key = keys[0]
    d = http_json(
        "https://api.minimaxi.com/v1/token_plan/remains",
        {
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        },
    )
    if (d.get("base_resp") or {}).get("status_code", 0) != 0:
        raise RuntimeError(d.get("base_resp"))
    remains = d.get("model_remains") or []
    general = next((m for m in remains if m.get("model_name") == "general"), remains[0])
    rows = [
        ("5H", f"{general.get('current_interval_remaining_percent')}% left", "general", fmt_ms(general.get("end_time"))),
        ("Weekly", f"{general.get('current_weekly_remaining_percent')}% left", "general", fmt_ms(general.get("weekly_end_time"))),
    ]
    video = next((m for m in remains if m.get("model_name") == "video"), None)
    if video:
        rows.append(("Video week", f"{video.get('current_weekly_remaining_percent')}% left", "video", fmt_ms(video.get("weekly_end_time"))))
    return "minimax-cn", rows


def main():
    print("=" * 72)
    print("智额 · SmartQuota — 4-provider live probe")
    print(datetime.now(CST).strftime("%Y-%m-%d %H:%M:%S %Z"))
    print("=" * 72)

    loaders = [
        ("ChatGPT", load_codex),
        ("Kimi", load_kimi),
        ("MiniMax", load_minimax),
        ("Grok", load_grok),
    ]

    for name, fn in loaders:
        print(f"\n## {name}")
        try:
            plan, rows = fn()
            print(f"plan/level: {plan}")
            print(f"{'window':<16} {'remaining':<14} {'detail':<18} reset")
            print("-" * 72)
            for window, rem, detail, reset in rows:
                print(f"{window:<16} {rem:<14} {detail:<18} {reset}")
            print("status: OK")
        except Exception as e:
            print(f"status: FAIL — {type(e).__name__}: {e}")

    print("\n" + "=" * 72)
    print("App providers registered in this product: codex / kimi / minimax / grok only")
    print("Settings: ~/.smartquota/settings.json")
    print("=" * 72)


if __name__ == "__main__":
    main()
