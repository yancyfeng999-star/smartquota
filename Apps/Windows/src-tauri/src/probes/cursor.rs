//! Cursor — read token from state.vscdb + usage-summary API (Mac CursorUsageProbe).

use crate::models::{parse_iso_unix, QuotaMeter};
use crate::paths::cursor_state_db_path;
use serde_json::Value;
use std::process::Command;

const USAGE_URL: &str = "https://cursor.com/api/usage-summary";

pub fn has_db() -> bool {
    cursor_state_db_path().exists()
}

fn read_access_token(db_path: &std::path::Path) -> Result<String, String> {
    // Prefer sqlite3 CLI if present
    let output = Command::new("sqlite3")
        .arg(db_path)
        .arg("SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'")
        .output();

    if let Ok(out) = output {
        if out.status.success() {
            let token = String::from_utf8_lossy(&out.stdout)
                .trim()
                .to_string();
            if !token.is_empty() {
                return Ok(token);
            }
        }
    }

    // Fallback: strings scan (fragile but works without sqlite3 on some machines)
    let bytes = std::fs::read(db_path).map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&bytes);
    // JWT-like token near cursorAuth
    if let Some(idx) = text.find("cursorAuth/accessToken") {
        let slice = &text[idx..idx.saturating_add(2000).min(text.len())];
        for part in slice.split(|c: char| c.is_whitespace() || c == '\0') {
            if part.starts_with("eyJ") && part.len() > 40 {
                return Ok(part.trim_matches(|c: char| !c.is_ascii_graphic()).to_string());
            }
        }
    }
    Err("无法从 Cursor 数据库读取 accessToken（请安装 sqlite3 或确认已登录 Cursor）".into())
}

fn b64url_decode(input: &str) -> Result<Vec<u8>, String> {
    fn dec(c: u8) -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'-' | b'+' => Some(62),
            b'_' | b'/' => Some(63),
            _ => None,
        }
    }
    let cleaned: Vec<u8> = input
        .bytes()
        .filter(|b| !b.is_ascii_whitespace())
        .collect();
    let mut out = Vec::with_capacity(cleaned.len() * 3 / 4);
    let mut i = 0;
    while i + 4 <= cleaned.len() {
        let a = dec(cleaned[i]).ok_or("b64")?;
        let b = dec(cleaned[i + 1]).ok_or("b64")?;
        let c = cleaned.get(i + 2).copied().filter(|&x| x != b'=').and_then(dec);
        let d = cleaned.get(i + 3).copied().filter(|&x| x != b'=').and_then(dec);
        out.push((a << 2) | (b >> 4));
        if let Some(c) = c {
            out.push(((b & 0xf) << 4) | (c >> 2));
            if let Some(d) = d {
                out.push(((c & 0x3) << 6) | d);
            }
        }
        i += 4;
    }
    // remainder
    let rem = &cleaned[i..];
    if rem.len() >= 2 {
        let a = dec(rem[0]).ok_or("b64")?;
        let b = dec(rem[1]).ok_or("b64")?;
        out.push((a << 2) | (b >> 4));
        if rem.len() >= 3 {
            if let Some(c) = dec(rem[2]) {
                out.push(((b & 0xf) << 4) | (c >> 2));
            }
        }
    }
    Ok(out)
}

fn extract_user_id_from_jwt(token: &str) -> Result<String, String> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        return Err("JWT 格式无效".into());
    }
    let decoded = b64url_decode(parts[1]).map_err(|_| "JWT payload 解码失败".to_string())?;
    let json: Value = serde_json::from_slice(&decoded).map_err(|e| e.to_string())?;
    json.get("sub")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "JWT 无 sub".into())
}

fn as_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

fn parse_usage_summary(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();
    let individual = json
        .get("individualUsage")
        .or_else(|| json.get("individual_usage"))
        .unwrap_or(json);

    if let Some(plan) = individual.get("plan") {
        let remaining = if let Some(used_pct) = as_f64(plan.get("totalPercentUsed"))
            .or_else(|| as_f64(plan.get("total_percent_used")))
        {
            Some((100.0 - used_pct).clamp(0.0, 100.0))
        } else if let (Some(used), Some(limit)) = (
            as_f64(plan.get("used")).or_else(|| as_f64(plan.get("requestsUsed"))),
            as_f64(plan.get("limit")).or_else(|| as_f64(plan.get("requestsLimit"))),
        ) {
            if limit > 0.0 {
                Some(((limit - used) / limit * 100.0).clamp(0.0, 100.0))
            } else {
                None
            }
        } else {
            None
        };

        let reset = plan
            .get("billingCycleEnd")
            .or_else(|| plan.get("billing_cycle_end"))
            .and_then(|v| v.as_str());
        meters.push(QuotaMeter::time_limit(
            "Plan",
            remaining,
            reset.map(|s| format!("周期至 {s}")),
            parse_iso_unix(reset),
        ));
    }

    if let Some(od) = individual.get("onDemand").or_else(|| individual.get("on_demand")) {
        if let Some(remaining_cents) = as_f64(od.get("remainingCents"))
            .or_else(|| as_f64(od.get("remaining_cents")))
        {
            meters.push(QuotaMeter::time_limit(
                "On-demand",
                None,
                Some(format!("剩余 ${:.2}", remaining_cents / 100.0)),
                None,
            ));
        }
    }

    if meters.is_empty() {
        return Err("Cursor usage-summary 无可用额度字段".into());
    }
    Ok(meters)
}

pub async fn probe_cursor() -> Result<Vec<QuotaMeter>, String> {
    let db = cursor_state_db_path();
    if !db.exists() {
        return Err(format!(
            "未找到 Cursor 数据库 {}。请安装并登录 Cursor。",
            db.display()
        ));
    }
    let token = read_access_token(&db)?;
    let user_id = extract_user_id_from_jwt(&token)?;
    let cookie = format!("WorkosCursorSessionToken={user_id}::{token}");

    let client = reqwest::Client::new();
    let resp = client
        .get(USAGE_URL)
        .header("Cookie", cookie)
        .header("Accept", "application/json")
        .header("User-Agent", "SmartQuota")
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| format!("Cursor 网络错误: {e}"))?;

    let status = resp.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("Cursor 鉴权失败，请重新登录 Cursor 应用".into());
    }
    if !status.is_success() {
        return Err(format!("Cursor HTTP {status}"));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_usage_summary(&json)
}
