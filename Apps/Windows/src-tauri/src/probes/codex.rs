use crate::models::QuotaMeter;
use crate::paths::codex_auth_path;
use serde_json::Value;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

const USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";
const REFRESH_URL: &str = "https://auth.openai.com/oauth/token";
const CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

struct CodexCreds {
    access_token: String,
    refresh_token: Option<String>,
    account_id: Option<String>,
    last_refresh: Option<String>,
    full: Value,
}

fn load_creds() -> Result<CodexCreds, String> {
    let path = codex_auth_path();
    if !path.exists() {
        return Err(format!(
            "未找到 {}，请先安装并登录 codex CLI",
            path.display()
        ));
    }
    let text = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let full: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let tokens = full
        .get("tokens")
        .ok_or_else(|| "auth.json 缺少 tokens".to_string())?;
    let access = tokens
        .get("access_token")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "auth.json 无 access_token（需 OAuth，不支持纯 API Key）".to_string())?
        .to_string();
    Ok(CodexCreds {
        access_token: access,
        refresh_token: tokens
            .get("refresh_token")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string()),
        account_id: tokens
            .get("account_id")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string()),
        last_refresh: full
            .get("last_refresh")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string()),
        full,
    })
}

fn needs_refresh(last_refresh: &Option<String>) -> bool {
    let Some(s) = last_refresh else {
        return true;
    };
    // If parse fails, try with existing token
    let Ok(dt) = chrono::DateTime::parse_from_rfc3339(s) else {
        return false;
    };
    let age = chrono::Utc::now().signed_duration_since(dt.with_timezone(&chrono::Utc));
    age.num_days() >= 8
}

async fn refresh_token(creds: &CodexCreds) -> Result<CodexCreds, String> {
    let refresh = creds
        .refresh_token
        .as_ref()
        .ok_or_else(|| "无 refresh_token，请重新运行 codex 登录".to_string())?;
    let client = reqwest::Client::new();
    let body = format!(
        "grant_type=refresh_token&client_id={}&refresh_token={}",
        urlencoding::encode(CLIENT_ID),
        urlencoding::encode(refresh)
    );
    let resp = client
        .post(REFRESH_URL)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| format!("刷新 token 网络错误: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!(
            "刷新 token 失败 HTTP {}，请重新运行 codex 登录",
            resp.status()
        ));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    let access = json
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "刷新响应无 access_token".to_string())?
        .to_string();
    let new_refresh = json
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| creds.refresh_token.clone());

    // Persist back to auth.json when possible
    let mut full = creds.full.clone();
    if let Some(tokens) = full.get_mut("tokens") {
        if let Some(obj) = tokens.as_object_mut() {
            obj.insert("access_token".into(), Value::String(access.clone()));
            if let Some(r) = &new_refresh {
                obj.insert("refresh_token".into(), Value::String(r.clone()));
            }
        }
    }
    full.as_object_mut().map(|o| {
        o.insert(
            "last_refresh".into(),
            Value::String(chrono::Utc::now().to_rfc3339()),
        )
    });
    let _ = fs::write(codex_auth_path(), serde_json::to_string_pretty(&full).unwrap_or_default());

    Ok(CodexCreds {
        access_token: access,
        refresh_token: new_refresh,
        account_id: creds.account_id.clone(),
        last_refresh: Some(chrono::Utc::now().to_rfc3339()),
        full,
    })
}

async fn fetch_usage(creds: &CodexCreds) -> Result<(Value, reqwest::header::HeaderMap), String> {
    let client = reqwest::Client::new();
    let mut req = client
        .get(USAGE_URL)
        .bearer_auth(&creds.access_token)
        .header("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(20));
    if let Some(aid) = &creds.account_id {
        req = req.header("ChatGPT-Account-ID", aid);
    }
    let resp = req.send().await.map_err(|e| format!("用量请求失败: {e}"))?;
    let status = resp.status();
    let headers = resp.headers().clone();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("AUTH".into());
    }
    if !status.is_success() {
        return Err(format!("用量 API HTTP {status}"));
    }
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    Ok((json, headers))
}

fn header_f64(headers: &reqwest::header::HeaderMap, key: &str) -> Option<f64> {
    headers
        .get(key)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse().ok())
}

fn window_seconds(window: Option<&Value>) -> Option<f64> {
    let w = window?;
    w.get("limit_window_seconds")
        .and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64)))
}

fn label_for_window(seconds: Option<f64>) -> &'static str {
    match seconds {
        Some(s) if s <= 6.0 * 3600.0 => "5 小时",
        Some(s) if s <= 10.0 * 24.0 * 3600.0 => "7 天",
        Some(_) => "月额度",
        None => "额度",
    }
}

fn reset_text(window: Option<&Value>) -> Option<String> {
    let w = window?;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_secs_f64();
    if let Some(reset_at) = w
        .get("reset_at")
        .and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64)))
    {
        let left = (reset_at - now).max(0.0);
        return Some(format_duration(left));
    }
    if let Some(after) = w
        .get("reset_after_seconds")
        .and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64)))
    {
        return Some(format_duration(after.max(0.0)));
    }
    None
}

fn format_duration(secs: f64) -> String {
    let s = secs as i64;
    let h = s / 3600;
    let m = (s % 3600) / 60;
    if h >= 48 {
        format!("{} 天后重置", h / 24)
    } else if h > 0 {
        format!("{h} 小时 {m} 分后重置")
    } else {
        format!("{m} 分后重置")
    }
}

fn parse_meters(json: &Value, headers: &reqwest::header::HeaderMap) -> Vec<QuotaMeter> {
    let rate = json.get("rate_limit");
    let primary = rate.and_then(|r| r.get("primary_window"));
    let secondary = rate.and_then(|r| r.get("secondary_window"));

    let mut meters = Vec::new();

    let primary_used = header_f64(headers, "x-codex-primary-used-percent").or_else(|| {
        primary
            .and_then(|w| w.get("used_percent"))
            .and_then(|v| v.as_f64())
    });
    if let Some(used) = primary_used {
        meters.push(QuotaMeter {
            label: label_for_window(window_seconds(primary)).into(),
            remaining_percent: Some((100.0 - used).clamp(0.0, 100.0)),
            reset_text: reset_text(primary),
        });
    }

    let secondary_used = header_f64(headers, "x-codex-secondary-used-percent").or_else(|| {
        secondary
            .and_then(|w| w.get("used_percent"))
            .and_then(|v| v.as_f64())
    });
    if let Some(used) = secondary_used {
        let label = label_for_window(window_seconds(secondary));
        if !meters.iter().any(|m| m.label == label) {
            meters.push(QuotaMeter {
                label: label.into(),
                remaining_percent: Some((100.0 - used).clamp(0.0, 100.0)),
                reset_text: reset_text(secondary),
            });
        }
    }

    meters
}

pub async fn probe_codex() -> Result<Vec<QuotaMeter>, String> {
    let mut creds = load_creds()?;
    if needs_refresh(&creds.last_refresh) {
        if let Ok(c) = refresh_token(&creds).await {
            creds = c;
        }
    }
    let (json, headers) = match fetch_usage(&creds).await {
        Ok(v) => v,
        Err(e) if e == "AUTH" => {
            creds = refresh_token(&creds).await?;
            fetch_usage(&creds).await?
        }
        Err(e) => return Err(e),
    };
    let meters = parse_meters(&json, &headers);
    if meters.is_empty() {
        return Err("用量响应中未找到额度窗口".into());
    }
    Ok(meters)
}
