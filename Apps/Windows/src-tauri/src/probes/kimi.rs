//! Kimi coding-plan probe — API Key first (Mac KimiUsageProbe coding path).

use crate::models::{parse_iso_unix, QuotaMeter};
use crate::paths::kimi_config_path;
use crate::secrets::{self, KIMI_API_KEY};
use serde_json::Value;
use std::fs;

const CODING_USAGE_URL: &str = "https://api.kimi.com/coding/v1/usages";
const AGENT_USAGE_URL: &str = "https://agent-gw.kimi.com/coding/v1/usages";

pub fn resolve_api_key() -> Option<String> {
    for env in ["KIMI_CODE_API_KEY", "KIMI_API_KEY", "KIMI_AUTH_TOKEN"] {
        if let Ok(v) = std::env::var(env) {
            if !v.is_empty() {
                return Some(v);
            }
        }
    }
    if let Some(k) = secrets::get_secret(KIMI_API_KEY) {
        return Some(k);
    }
    // Optional local config
    let path = kimi_config_path();
    if let Ok(text) = fs::read_to_string(path) {
        if let Ok(json) = serde_json::from_str::<Value>(&text) {
            for key in ["api_key", "apiKey", "token"] {
                if let Some(s) = json.get(key).and_then(|v| v.as_str()) {
                    if s.starts_with("sk-kimi") || s.len() > 20 {
                        return Some(s.to_string());
                    }
                }
            }
        }
    }
    None
}

fn parse_num_pair(limit: Option<&str>, used: Option<&str>, remaining: Option<&str>) -> (f64, f64, f64) {
    let lim = limit.and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0);
    let rem = remaining
        .and_then(|s| s.parse::<f64>().ok())
        .or_else(|| {
            let u = used.and_then(|s| s.parse::<f64>().ok())?;
            if lim > 0.0 {
                Some((lim - u).max(0.0))
            } else {
                None
            }
        })
        .unwrap_or(0.0);
    let u = used
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or_else(|| (lim - rem).max(0.0));
    (lim, u, rem)
}

fn field_str(obj: &Value, keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Some(s) = obj.get(*k).and_then(|v| v.as_str()) {
            return Some(s.to_string());
        }
        if let Some(n) = obj.get(*k).and_then(|v| v.as_i64()) {
            return Some(n.to_string());
        }
        if let Some(n) = obj.get(*k).and_then(|v| v.as_f64()) {
            return Some(n.to_string());
        }
    }
    None
}

fn parse_coding_json(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();

    // Weekly from usage
    if let Some(usage) = json.get("usage") {
        let limit = field_str(usage, &["limit"]);
        let used = field_str(usage, &["used"]);
        let remaining = field_str(usage, &["remaining"]);
        let (lim, u, rem) = parse_num_pair(
            limit.as_deref(),
            used.as_deref(),
            remaining.as_deref(),
        );
        if lim > 0.0 {
            let pct = rem / lim * 100.0;
            let reset = field_str(usage, &["resetTime", "reset_time"]);
            meters.push(QuotaMeter::weekly(
                Some(pct.clamp(0.0, 100.0)),
                Some(format!("{u}/{lim} weekly")),
                parse_iso_unix(reset.as_deref()),
            ));
        }
    }

    // 5h from limits[]
    if let Some(limits) = json.get("limits").and_then(|v| v.as_array()) {
        let rate = limits
            .iter()
            .find(|l| {
                let w = l.get("window");
                let dur = w.and_then(|x| x.get("duration")).and_then(|d| d.as_i64());
                let unit = w
                    .and_then(|x| x.get("timeUnit").or_else(|| x.get("time_unit")))
                    .and_then(|u| u.as_str())
                    .unwrap_or("");
                dur == Some(300) && unit.contains("MINUTE")
            })
            .or_else(|| limits.first());

        if let Some(rate) = rate {
            let detail = rate.get("detail").unwrap_or(rate);
            let limit = field_str(detail, &["limit"]);
            let used = field_str(detail, &["used"]);
            let remaining = field_str(detail, &["remaining"]);
            let (lim, u, rem) = parse_num_pair(
                limit.as_deref(),
                used.as_deref(),
                remaining.as_deref(),
            );
            if lim > 0.0 {
                let pct = rem / lim * 100.0;
                let reset = field_str(detail, &["resetTime", "reset_time"]);
                meters.push(QuotaMeter::session(
                    Some(pct.clamp(0.0, 100.0)),
                    Some(format!("{u}/{lim} (5h)")),
                    parse_iso_unix(reset.as_deref()),
                ));
            }
        }
    }

    // Monthly totalQuota
    if let Some(total) = json.get("totalQuota").or_else(|| json.get("total_quota")) {
        let limit = field_str(total, &["limit"]);
        let used = field_str(total, &["used"]);
        let remaining = field_str(total, &["remaining"]);
        let (lim, u, rem) = parse_num_pair(
            limit.as_deref(),
            used.as_deref(),
            remaining.as_deref(),
        );
        if lim > 0.0 {
            let pct = rem / lim * 100.0;
            let reset = field_str(total, &["resetTime", "reset_time"]);
            meters.push(QuotaMeter::time_limit(
                "总额",
                Some(pct.clamp(0.0, 100.0)),
                Some(format!("{u}/{lim} 总额")),
                parse_iso_unix(reset.as_deref()),
            ));
        }
    }

    if meters.is_empty() {
        return Err("Kimi 响应中无额度字段".into());
    }
    Ok(meters)
}

async fn fetch_json(url: &str, api_key: &str) -> Result<Value, String> {
    let client = reqwest::Client::new();
    let resp = client
        .get(url)
        .bearer_auth(api_key)
        .header("Accept", "application/json")
        .header("User-Agent", "Desktop Kimi Work")
        .timeout(std::time::Duration::from_secs(25))
        .send()
        .await
        .map_err(|e| format!("Kimi 网络错误: {e}"))?;
    let status = resp.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("Kimi 鉴权失败，请检查 sk-kimi API Key".into());
    }
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        return Err(format!("Kimi HTTP {status}: {}", body.chars().take(200).collect::<String>()));
    }
    resp.json().await.map_err(|e| e.to_string())
}

pub async fn probe_kimi() -> Result<Vec<QuotaMeter>, String> {
    let key = resolve_api_key().ok_or_else(|| {
        "未配置 Kimi API Key：在设置中粘贴 sk-kimi-…，或设置环境变量 KIMI_API_KEY".to_string()
    })?;

    let json = fetch_json(CODING_USAGE_URL, &key).await?;
    let mut meters = parse_coding_json(&json)?;

    // Optional monthly from agent-gw if missing
    if !meters.iter().any(|m| m.key.starts_with("time:")) {
        if let Ok(agent) = fetch_json(AGENT_USAGE_URL, &key).await {
            if let Ok(extra) = parse_coding_json(&agent) {
                for m in extra {
                    if m.key.starts_with("time:") && !meters.iter().any(|x| x.key == m.key) {
                        meters.push(m);
                    }
                }
            }
        }
    }

    Ok(meters)
}
