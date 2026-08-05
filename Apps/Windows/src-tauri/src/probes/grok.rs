use crate::models::QuotaMeter;
use crate::paths::grok_auth_path;
use serde_json::Value;
use std::fs;

const BILLING_URL: &str = "https://cli-chat-proxy.grok.com/v1/billing?format=credits";
const DEFAULT_ISSUER: &str = "https://auth.x.ai";

struct GrokCreds {
    access_token: String,
    refresh_token: Option<String>,
    oidc_issuer: Option<String>,
    oidc_client_id: Option<String>,
    entry_key: String,
    full: Value,
}

fn load_creds() -> Result<GrokCreds, String> {
    let path = grok_auth_path();
    if !path.exists() {
        return Err(format!(
            "未找到 {}，请先运行 grok login",
            path.display()
        ));
    }
    let text = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let full: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let obj = full
        .as_object()
        .ok_or_else(|| "auth.json 格式无效".to_string())?;

    let mut best: Option<GrokCreds> = None;
    for (key, entry) in obj {
        let access = entry
            .get("key")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty());
        let Some(access) = access else { continue };
        let refresh = entry
            .get("refresh_token")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());
        let candidate = GrokCreds {
            access_token: access.to_string(),
            refresh_token: refresh.clone(),
            oidc_issuer: entry
                .get("oidc_issuer")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            oidc_client_id: entry
                .get("oidc_client_id")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            entry_key: key.clone(),
            full: full.clone(),
        };
        // Prefer entries with refresh token
        match &best {
            None => best = Some(candidate),
            Some(b) if b.refresh_token.is_none() && refresh.is_some() => best = Some(candidate),
            _ => {}
        }
    }
    best.ok_or_else(|| "auth.json 中无可用 token".to_string())
}

async fn refresh_token(creds: &GrokCreds) -> Result<GrokCreds, String> {
    let refresh = creds
        .refresh_token
        .as_ref()
        .ok_or_else(|| "无 refresh_token，请重新 grok login".to_string())?;
    let issuer = creds
        .oidc_issuer
        .clone()
        .unwrap_or_else(|| DEFAULT_ISSUER.into());
    let url = if issuer.ends_with('/') {
        format!("{issuer}oauth2/token")
    } else {
        format!("{issuer}/oauth2/token")
    };
    let mut body = format!(
        "grant_type=refresh_token&refresh_token={}",
        urlencoding::encode(refresh)
    );
    if let Some(cid) = &creds.oidc_client_id {
        body.push_str(&format!("&client_id={}", urlencoding::encode(cid)));
    }
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| format!("Grok 刷新 token 失败: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!(
            "Grok 刷新失败 HTTP {}，请重新 grok login",
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

    let mut full = creds.full.clone();
    if let Some(entry) = full
        .as_object_mut()
        .and_then(|o| o.get_mut(&creds.entry_key))
        .and_then(|e| e.as_object_mut())
    {
        entry.insert("key".into(), Value::String(access.clone()));
        if let Some(r) = &new_refresh {
            entry.insert("refresh_token".into(), Value::String(r.clone()));
        }
    }
    let _ = fs::write(grok_auth_path(), serde_json::to_string_pretty(&full).unwrap_or_default());

    Ok(GrokCreds {
        access_token: access,
        refresh_token: new_refresh,
        oidc_issuer: creds.oidc_issuer.clone(),
        oidc_client_id: creds.oidc_client_id.clone(),
        entry_key: creds.entry_key.clone(),
        full,
    })
}

async fn fetch_billing(token: &str) -> Result<Value, String> {
    let client = reqwest::Client::new();
    let resp = client
        .get(BILLING_URL)
        .bearer_auth(token)
        .header("Accept", "application/json")
        .header("x-grok-client-mode", "build")
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| format!("Grok billing 请求失败: {e}"))?;
    let status = resp.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("AUTH".into());
    }
    if !status.is_success() {
        return Err(format!("Grok billing HTTP {status}"));
    }
    resp.json().await.map_err(|e| e.to_string())
}

fn as_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

fn parse_meters(root: &Value) -> Vec<QuotaMeter> {
    let config = root.get("config").unwrap_or(root);
    let mut meters = Vec::new();

    if let Some(pct) = as_f64(config.get("creditUsagePercent")) {
        let period = config.get("currentPeriod");
        let ptype = period
            .and_then(|p| p.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let end_str = period.and_then(|p| p.get("end")).and_then(|e| e.as_str());
        let reset_text = end_str.map(|s| format!("重置: {s}"));
        let resets_at = crate::models::parse_iso_unix(end_str);
        let rem = Some((100.0 - pct).clamp(-100.0, 100.0));
        if ptype.contains("WEEK") {
            meters.push(QuotaMeter::weekly(rem, reset_text, resets_at));
        } else if ptype.contains("MONTH") {
            meters.push(QuotaMeter::time_limit("本月额度", rem, reset_text, resets_at));
        } else {
            meters.push(QuotaMeter::time_limit("额度", rem, reset_text, resets_at));
        }
    }

    if let Some(products) = config.get("productUsage").and_then(|v| v.as_array()) {
        for p in products {
            let name = p.get("product").and_then(|v| v.as_str()).unwrap_or("Product");
            if let Some(pct) = as_f64(p.get("usagePercent")) {
                meters.push(QuotaMeter::model(
                    name,
                    Some((100.0 - pct).clamp(-100.0, 100.0)),
                    None,
                    None,
                ));
            }
        }
    }
    meters
}

pub async fn probe_grok() -> Result<Vec<QuotaMeter>, String> {
    let mut creds = load_creds()?;
    let json = match fetch_billing(&creds.access_token).await {
        Ok(j) => j,
        Err(e) if e == "AUTH" => {
            creds = refresh_token(&creds).await?;
            fetch_billing(&creds.access_token).await?
        }
        Err(e) => return Err(e),
    };
    let meters = parse_meters(&json);
    if meters.is_empty() {
        return Err("billing 响应中无额度字段".into());
    }
    Ok(meters)
}
