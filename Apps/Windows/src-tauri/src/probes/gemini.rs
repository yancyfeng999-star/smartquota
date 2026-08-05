//! Gemini — read `~/.gemini/oauth_creds.json` + Cloud Code Assist quota API (Mac GeminiAPIProbe simplified).

use crate::models::QuotaMeter;
use crate::paths::gemini_oauth_path;
use serde_json::Value;
use std::fs;

// Cloud Code Assist loadCodeAssist (same family as Mac)
const QUOTA_URL: &str =
    "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist";

pub fn has_creds() -> bool {
    gemini_oauth_path().exists()
}

fn load_access_token() -> Result<String, String> {
    let path = gemini_oauth_path();
    if !path.exists() {
        return Err(format!(
            "未找到 {}，请安装 Gemini CLI 并登录",
            path.display()
        ));
    }
    let text = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let json: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    json.get("access_token")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .ok_or_else(|| "oauth_creds.json 无 access_token".into())
}

fn as_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

fn parse_quota_response(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();

    // Walk nested buckets for remaining fraction / percent
    fn walk(v: &Value, meters: &mut Vec<QuotaMeter>) {
        match v {
            Value::Object(map) => {
                // remainingFraction style
                if let Some(frac) = as_f64(map.get("remainingFraction"))
                    .or_else(|| as_f64(map.get("remaining_fraction")))
                {
                    let name = map
                        .get("displayName")
                        .or_else(|| map.get("modelId"))
                        .or_else(|| map.get("id"))
                        .and_then(|x| x.as_str())
                        .unwrap_or("Gemini");
                    meters.push(QuotaMeter::model(
                        name,
                        Some((frac * 100.0).clamp(0.0, 100.0)),
                        None,
                        None,
                    ));
                }
                if let (Some(remaining), Some(limit)) = (
                    as_f64(map.get("remaining")),
                    as_f64(map.get("limit")).or_else(|| as_f64(map.get("quota"))),
                ) {
                    if limit > 0.0 {
                        let name = map
                            .get("displayName")
                            .or_else(|| map.get("modelId"))
                            .and_then(|x| x.as_str())
                            .unwrap_or("Gemini");
                        meters.push(QuotaMeter::model(
                            name,
                            Some((remaining / limit * 100.0).clamp(0.0, 100.0)),
                            None,
                            None,
                        ));
                    }
                }
                for val in map.values() {
                    walk(val, meters);
                }
            }
            Value::Array(arr) => {
                for item in arr {
                    walk(item, meters);
                }
            }
            _ => {}
        }
    }

    walk(json, &mut meters);

    // Dedupe by label keep first
    let mut seen = std::collections::HashSet::new();
    meters.retain(|m| seen.insert(m.label.clone()));

    if meters.is_empty() {
        // Creds valid enough to call API but no buckets — report healthy placeholder session
        return Err("Gemini 额度响应无可解析字段（可能需更新 CLI 登录）".into());
    }
    Ok(meters)
}

pub async fn probe_gemini() -> Result<Vec<QuotaMeter>, String> {
    let token = load_access_token()?;
    let client = reqwest::Client::new();
    let resp = client
        .post(QUOTA_URL)
        .bearer_auth(&token)
        .header("Content-Type", "application/json")
        .body("{}")
        .timeout(std::time::Duration::from_secs(25))
        .send()
        .await
        .map_err(|e| format!("Gemini 网络错误: {e}"))?;

    let status = resp.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("Gemini 鉴权失败，请重新 gemini 登录刷新 token".into());
    }
    if !status.is_success() {
        return Err(format!("Gemini HTTP {status}"));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_quota_response(&json)
}
