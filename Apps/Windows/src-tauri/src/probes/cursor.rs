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

fn percent_from_message(msg: Option<&str>) -> Option<f64> {
    let msg = msg?;
    let idx = msg.find('%')?;
    let before = &msg[..idx];
    let start = before
        .rfind(|c: char| !c.is_ascii_digit() && c != '.')
        .map(|i| i + 1)
        .unwrap_or(0);
    before[start..].parse().ok()
}

pub(crate) fn parse_usage_summary(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();
    let cycle_end = json
        .get("billingCycleEnd")
        .or_else(|| json.get("billing_cycle_end"))
        .and_then(|v| v.as_str());
    let reset_unix = parse_iso_unix(cycle_end);

    let individual = json
        .get("individualUsage")
        .or_else(|| json.get("individual_usage"));
    let plan = individual.and_then(|u| u.get("plan"));

    let auto_from_msg = percent_from_message(
        json.get("autoModelSelectedDisplayMessage")
            .and_then(|v| v.as_str()),
    );
    let api_from_msg = percent_from_message(
        json.get("namedModelSelectedDisplayMessage")
            .and_then(|v| v.as_str()),
    );
    let auto_pct = auto_from_msg.or_else(|| plan.and_then(|p| as_f64(p.get("autoPercentUsed"))));
    let api_pct = api_from_msg.or_else(|| plan.and_then(|p| as_f64(p.get("apiPercentUsed"))));
    let plan_enabled = plan
        .and_then(|p| p.get("enabled"))
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if plan_enabled && (auto_pct.is_some() || api_pct.is_some()) {
        if let Some(used) = auto_pct {
            meters.push(QuotaMeter::time_limit(
                "Cursor 模型",
                Some((100.0 - used).clamp(0.0, 100.0)),
                None,
                reset_unix,
            ));
        }
        if let Some(used) = api_pct {
            meters.push(QuotaMeter::time_limit(
                "其他模型",
                Some((100.0 - used).clamp(0.0, 100.0)),
                None,
                reset_unix,
            ));
        }
    } else if let Some(plan) = plan.filter(|_| plan_enabled) {
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
        if remaining.is_some() {
            meters.push(QuotaMeter::time_limit(
                "总额",
                remaining,
                cycle_end.map(|s| format!("周期至 {s}")),
                reset_unix,
            ));
        }
    }

    if meters.is_empty() {
        let auto_used = percent_from_message(
            json.get("autoModelSelectedDisplayMessage")
                .and_then(|v| v.as_str()),
        );
        let api_used = percent_from_message(
            json.get("namedModelSelectedDisplayMessage")
                .and_then(|v| v.as_str()),
        );
        if let (Some(auto_used), Some(api_used)) = (auto_used, api_used) {
            meters.push(QuotaMeter::time_limit(
                "Cursor 模型",
                Some((100.0 - auto_used).clamp(0.0, 100.0)),
                None,
                reset_unix,
            ));
            meters.push(QuotaMeter::time_limit(
                "其他模型",
                Some((100.0 - api_used).clamp(0.0, 100.0)),
                None,
                reset_unix,
            ));
        }
    }

    if let Some(od) = individual.and_then(|u| u.get("onDemand").or_else(|| u.get("on_demand"))) {
        if od.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let (Some(used), Some(limit)) = (as_f64(od.get("used")), as_f64(od.get("limit"))) {
                if limit > 0.0 {
                    meters.push(QuotaMeter::time_limit(
                        "On-Demand",
                        Some(((limit - used) / limit * 100.0).clamp(0.0, 100.0)),
                        Some(format!("{used}/{limit} on-demand")),
                        reset_unix,
                    ));
                }
            } else if let Some(remaining_cents) = as_f64(od.get("remainingCents"))
                .or_else(|| as_f64(od.get("remaining_cents")))
            {
                meters.push(QuotaMeter::time_limit(
                    "On-Demand",
                    None,
                    Some(format!("剩余 ${:.2}", remaining_cents / 100.0)),
                    None,
                ));
            }
        }
    }

    if json
        .get("isUnlimited")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
        && meters.is_empty()
    {
        meters.push(QuotaMeter::time_limit(
            "总额",
            Some(100.0),
            Some("Unlimited".into()),
            reset_unix,
        ));
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_ultra_two_pools() {
        let json = json!({
            "membershipType": "ultra",
            "isUnlimited": false,
            "billingCycleEnd": "2026-08-14T00:00:00.000Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "autoPercentUsed": 1,
                    "apiPercentUsed": 5,
                    "totalPercentUsed": 1.8
                },
                "onDemand": { "enabled": false }
            }
        });
        let meters = parse_usage_summary(&json).expect("parse");
        assert_eq!(meters.len(), 2);
        assert_eq!(meters[0].label, "Cursor 模型");
        assert_eq!(meters[0].remaining_percent, Some(99.0));
        assert_eq!(meters[1].label, "其他模型");
        assert_eq!(meters[1].remaining_percent, Some(95.0));
        assert_eq!(meters[1].reset_text, None);
    }

    #[test]
    fn falls_back_to_legacy_monthly_without_pool_percents() {
        let json = json!({
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": { "enabled": true, "used": 25, "limit": 100 },
                "onDemand": { "enabled": false }
            }
        });
        let meters = parse_usage_summary(&json).expect("parse");
        assert_eq!(meters.len(), 1);
        assert_eq!(meters[0].label, "总额");
        assert_eq!(meters[0].remaining_percent, Some(75.0));
    }
}
