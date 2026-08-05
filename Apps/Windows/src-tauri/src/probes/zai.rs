//! Z.ai / 智谱 Coding Plan — Mac `ZaiUsageProbe`.

use crate::models::{parse_iso_unix, QuotaMeter};
use crate::paths::home;
use crate::secrets::{self, provider_key_account};
use serde_json::Value;
use std::fs;

const ENDPOINTS: &[&str] = &[
    "https://api.z.ai",
    "https://open.bigmodel.cn",
    "https://dev.bigmodel.cn",
];

pub fn resolve_key() -> Option<String> {
    for env in ["ZAI_API_KEY", "Z_AI_API_KEY", "ZHIPU_API_KEY", "BIGMODEL_API_KEY"] {
        if let Ok(v) = std::env::var(env) {
            if !v.is_empty() {
                return Some(v);
            }
        }
    }
    if let Some(k) = secrets::get_secret(&provider_key_account("zai")) {
        return Some(k);
    }
    // Claude settings.json providers
    let path = home().join(".claude").join("settings.json");
    if let Ok(text) = fs::read_to_string(path) {
        if let Ok(json) = serde_json::from_str::<Value>(&text) {
            if let Some(key) = extract_key_from_claude_settings(&json) {
                return Some(key);
            }
        }
    }
    None
}

fn extract_key_from_claude_settings(json: &Value) -> Option<String> {
    // env.ANTHROPIC_AUTH_TOKEN / apiKeyHelper paths vary
    if let Some(env) = json.get("env") {
        for k in ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ZAI_API_KEY"] {
            if let Some(s) = env.get(k).and_then(|v| v.as_str()) {
                if !s.is_empty() {
                    return Some(s.to_string());
                }
            }
        }
    }
    walk_for_api_key(json)
}

fn walk_for_api_key(v: &Value) -> Option<String> {
    match v {
        Value::Object(map) => {
            for key in ["api_key", "apiKey", "token", "authToken"] {
                if let Some(s) = map.get(key).and_then(|x| x.as_str()) {
                    if s.len() > 8 {
                        return Some(s.to_string());
                    }
                }
            }
            for val in map.values() {
                if let Some(k) = walk_for_api_key(val) {
                    return Some(k);
                }
            }
            None
        }
        Value::Array(arr) => {
            for item in arr {
                if let Some(k) = walk_for_api_key(item) {
                    return Some(k);
                }
            }
            None
        }
        _ => None,
    }
}

pub fn has_config() -> bool {
    resolve_key().is_some()
}

fn parse_limits(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let limits = json
        .pointer("/data/limits")
        .or_else(|| json.get("limits"))
        .and_then(|v| v.as_array())
        .ok_or_else(|| "Z.ai 响应无 limits".to_string())?;

    let mut meters = Vec::new();
    for limit in limits {
        let typ = limit
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let unit = limit.get("unit").and_then(|v| v.as_i64());
        let percentage = limit
            .get("percentage")
            .and_then(|v| v.as_f64())
            .or_else(|| limit.get("percentage").and_then(|v| v.as_i64()).map(|i| i as f64))
            .unwrap_or(0.0);
        let rem = (100.0 - percentage.clamp(0.0, 100.0)).clamp(0.0, 100.0);
        let reset = limit
            .get("nextResetTime")
            .or_else(|| limit.get("next_reset_time"));
        let reset_unix = reset
            .and_then(|v| v.as_i64())
            .map(|ms| if ms > 1_000_000_000_000 { ms / 1000 } else { ms })
            .or_else(|| parse_iso_unix(reset.and_then(|v| v.as_str())));
        let reset_text = reset.and_then(|v| {
            if let Some(s) = v.as_str() {
                Some(s.to_string())
            } else {
                v.as_i64().map(|ms| format!("reset {ms}"))
            }
        });

        let meter = match (typ, unit) {
            ("TIME_LIMIT", _) => QuotaMeter::time_limit("MCP", Some(rem), reset_text, reset_unix),
            ("TOKENS_LIMIT", Some(3)) | ("TOKENS_LIMIT", None) => {
                QuotaMeter::session(Some(rem), reset_text, reset_unix)
            }
            ("TOKENS_LIMIT", Some(6)) => QuotaMeter::weekly(Some(rem), reset_text, reset_unix),
            ("TOKENS_LIMIT", Some(7)) => {
                QuotaMeter::time_limit("Monthly", Some(rem), reset_text, reset_unix)
            }
            ("TOKENS_LIMIT", Some(u)) => {
                QuotaMeter::model(&format!("Tokens u{u}"), Some(rem), reset_text, reset_unix)
            }
            _ => continue,
        };
        meters.push(meter);
    }
    if meters.is_empty() {
        return Err("Z.ai 无已识别额度类型".into());
    }
    Ok(meters)
}

pub async fn probe_zai() -> Result<Vec<QuotaMeter>, String> {
    let key = resolve_key().ok_or_else(|| {
        "未配置 Z.ai Key：设置扩展 Key、环境变量 ZAI_API_KEY，或在 ~/.claude/settings.json 配置"
            .to_string()
    })?;
    let client = reqwest::Client::new();
    let mut last = "Z.ai: 全部端点失败".to_string();
    for base in ENDPOINTS {
        let url = format!("{base}/api/monitor/usage/quota/limit");
        match client
            .get(&url)
            .bearer_auth(&key)
            .header("Accept", "application/json")
            .header("Accept-Language", "en-US,en")
            .timeout(std::time::Duration::from_secs(15))
            .send()
            .await
        {
            Ok(resp) => {
                let status = resp.status();
                if status.as_u16() == 401 || status.as_u16() == 403 {
                    return Err("Z.ai 鉴权失败".into());
                }
                if !status.is_success() {
                    last = format!("Z.ai HTTP {status} @ {base}");
                    continue;
                }
                let json: Value = resp.json().await.map_err(|e| e.to_string())?;
                return parse_limits(&json);
            }
            Err(e) => last = format!("{base}: {e}"),
        }
    }
    Err(last)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_sample_limits() {
        let json = serde_json::json!({
            "data": {
                "limits": [
                    {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 20},
                    {"type": "TOKENS_LIMIT", "unit": 6, "percentage": 40},
                    {"type": "TIME_LIMIT", "unit": 5, "percentage": 10}
                ]
            }
        });
        let m = parse_limits(&json).unwrap();
        assert_eq!(m.len(), 3);
        assert!(m.iter().any(|x| x.kind == "session" && x.remaining_percent == Some(80.0)));
        assert!(m.iter().any(|x| x.kind == "weekly" && x.remaining_percent == Some(60.0)));
    }
}
