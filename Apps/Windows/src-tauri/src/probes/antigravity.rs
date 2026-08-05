//! Antigravity — local language_server process + localhost API (Mac simplified for Windows).

use crate::models::QuotaMeter;
use serde_json::Value;
use std::process::Command;

pub fn available() -> bool {
    // Windows: tasklist | findstr language_server
    #[cfg(target_os = "windows")]
    {
        Command::new("tasklist")
            .output()
            .map(|o| {
                let s = String::from_utf8_lossy(&o.stdout).to_lowercase();
                s.contains("language_server") || s.contains("antigravity")
            })
            .unwrap_or(false)
    }
    #[cfg(not(target_os = "windows"))]
    {
        Command::new("pgrep")
            .args(["-f", "language_server"])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }
}

pub async fn probe_antigravity() -> Result<Vec<QuotaMeter>, String> {
    if !available() {
        return Err(
            "未检测到 Antigravity language_server 进程。请先启动 Antigravity。".into(),
        );
    }

    // Try common local ports used by Antigravity / language servers
    let client = reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .map_err(|e| e.to_string())?;

    let paths = [
        "/api/user-status",
        "/user-status",
        "/api/quota",
        "/quota",
        "/api/v1/user",
    ];
    let ports: Vec<u16> = (3000..3010).chain(4000..4010).chain(5000..5010).chain([8080, 8443, 9240, 9241]).collect();

    let mut last = "未找到可用本地 API".to_string();
    for port in ports {
        for path in paths {
            for scheme in ["http", "https"] {
                let url = format!("{scheme}://127.0.0.1:{port}{path}");
                if let Ok(resp) = client.get(&url).send().await {
                    if resp.status().is_success() {
                        if let Ok(json) = resp.json::<Value>().await {
                            if let Ok(m) = parse_user_status(&json) {
                                return Ok(m);
                            }
                            last = format!("端口 {port} 响应无法解析");
                        }
                    }
                }
            }
        }
    }
    Err(format!(
        "检测到进程但无法拉取额度。{last}（Mac 版会扫 PID 监听端口；Windows 已扫常用端口）"
    ))
}

fn parse_user_status(json: &Value) -> Result<Vec<QuotaMeter>, String> {
    let mut meters = Vec::new();
    // Try nested quota fields
    fn walk(v: &Value, meters: &mut Vec<QuotaMeter>) {
        match v {
            Value::Object(map) => {
                if let Some(frac) = map
                    .get("remainingFraction")
                    .or_else(|| map.get("remaining_fraction"))
                    .and_then(|x| x.as_f64())
                {
                    let name = map
                        .get("name")
                        .or_else(|| map.get("model"))
                        .and_then(|x| x.as_str())
                        .unwrap_or("Quota");
                    meters.push(QuotaMeter::model(
                        name,
                        Some((frac * 100.0).clamp(0.0, 100.0)),
                        None,
                        None,
                    ));
                }
                if let Some(pct) = map
                    .get("percentRemaining")
                    .or_else(|| map.get("remainingPercent"))
                    .and_then(|x| x.as_f64())
                {
                    let name = map
                        .get("name")
                        .and_then(|x| x.as_str())
                        .unwrap_or("Quota");
                    meters.push(QuotaMeter::model(name, Some(pct.clamp(0.0, 100.0)), None, None));
                }
                for val in map.values() {
                    walk(val, meters);
                }
            }
            Value::Array(a) => {
                for i in a {
                    walk(i, meters);
                }
            }
            _ => {}
        }
    }
    walk(json, &mut meters);
    if meters.is_empty() {
        return Err("JSON 无额度字段".into());
    }
    Ok(meters)
}
