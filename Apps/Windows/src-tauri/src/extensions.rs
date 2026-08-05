//! User script extensions — Mac `~/.smartquota/extensions` parity.

use crate::models::QuotaMeter;
use crate::paths::config_dir;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtensionInfo {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: Option<String>,
    pub path: String,
    pub sections: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RawManifest {
    id: String,
    name: String,
    version: String,
    description: Option<String>,
    sections: Vec<RawSection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RawSection {
    id: String,
    #[serde(rename = "type")]
    section_type: Option<String>,
    probe: RawProbe,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RawProbe {
    command: Option<String>,
    url: Option<String>,
    #[serde(rename = "builtIn")]
    built_in: Option<String>,
    interval: Option<u64>,
    timeout: Option<u64>,
}

pub fn extensions_dir() -> PathBuf {
    config_dir().join("extensions")
}

pub fn list_extensions() -> Vec<ExtensionInfo> {
    let dir = extensions_dir();
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(&dir) else {
        return out;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let manifest_path = path.join("manifest.json");
        if !manifest_path.exists() {
            continue;
        }
        let Ok(text) = fs::read_to_string(&manifest_path) else {
            continue;
        };
        let Ok(raw) = serde_json::from_str::<RawManifest>(&text) else {
            continue;
        };
        out.push(ExtensionInfo {
            id: format!("ext-{}", raw.id),
            name: raw.name,
            version: raw.version,
            description: raw.description,
            path: path.display().to_string(),
            sections: raw.sections.len(),
        });
    }
    out
}

/// Probe all extensions; returns cards as (id, name, meters|error).
pub async fn probe_all_extensions() -> Vec<(String, String, Result<Vec<QuotaMeter>, String>)> {
    let infos = list_extensions();
    let mut results = Vec::new();
    for info in infos {
        let name = info.name.clone();
        let id = info.id.clone();
        let res = probe_extension_dir(PathBuf::from(&info.path)).await;
        results.push((id, name, res));
    }
    results
}

async fn probe_extension_dir(dir: PathBuf) -> Result<Vec<QuotaMeter>, String> {
    let text = fs::read_to_string(dir.join("manifest.json")).map_err(|e| e.to_string())?;
    let raw: RawManifest = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let mut meters = Vec::new();

    for section in raw.sections {
        let timeout = section.probe.timeout.unwrap_or(10);
        if let Some(cmd) = &section.probe.command {
            // Security: only allow commands under the extension directory or shell scripts named without path escape
            let cmd_path = dir.join(cmd);
            let run = if cmd_path.exists() {
                Command::new(&cmd_path)
                    .current_dir(&dir)
                    .output()
            } else if !cmd.contains("..") && !cmd.starts_with('/') && !cmd.contains(':') {
                // relative script
                Command::new("cmd")
                    .args(["/C", cmd])
                    .current_dir(&dir)
                    .output()
            } else {
                return Err(format!("扩展命令不安全或未找到: {cmd}"));
            };
            let output = run.map_err(|e| format!("扩展脚本失败: {e}"))?;
            let stdout = String::from_utf8_lossy(&output.stdout);
            // Expect JSON: { "meters": [ { "label", "remainingPercent", "resetText" } ] }
            // or { "quotas": [...] }
            if let Ok(json) = serde_json::from_str::<Value>(stdout.trim()) {
                meters.extend(parse_extension_json(&json, &section.id));
            } else {
                // plain percent lines
                if let Ok(re) = regex::Regex::new(r"(\d{1,3})\s*%") {
                    if let Some(cap) = re.captures(&stdout) {
                        let p: f64 = cap[1].parse().unwrap_or(0.0);
                        meters.push(QuotaMeter::time_limit(
                            &section.id,
                            Some(p.clamp(0.0, 100.0)),
                            Some(stdout.lines().next().unwrap_or("").to_string()),
                            None,
                        ));
                    }
                }
            }
            let _ = timeout;
        } else if section.probe.built_in.as_deref() == Some("healthCheck") {
            if let Some(url) = &section.probe.url {
                if !(url.starts_with("http://") || url.starts_with("https://")) {
                    return Err("healthCheck 仅允许 http(s)".into());
                }
                let client = reqwest::Client::new();
                let resp = client
                    .get(url)
                    .timeout(std::time::Duration::from_secs(timeout.max(1)))
                    .send()
                    .await
                    .map_err(|e| e.to_string())?;
                let ok = resp.status().is_success();
                meters.push(QuotaMeter::time_limit(
                    &section.id,
                    Some(if ok { 100.0 } else { 0.0 }),
                    Some(format!("health HTTP {}", resp.status())),
                    None,
                ));
            }
        }
    }

    if meters.is_empty() {
        return Err("扩展未产出额度数据".into());
    }
    Ok(meters)
}

fn parse_extension_json(json: &Value, section_id: &str) -> Vec<QuotaMeter> {
    let mut meters = Vec::new();
    let arr = json
        .get("meters")
        .or_else(|| json.get("quotas"))
        .and_then(|v| v.as_array());
    if let Some(items) = arr {
        for item in items {
            let label = item
                .get("label")
                .or_else(|| item.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or(section_id);
            let rem = item
                .get("remainingPercent")
                .or_else(|| item.get("remaining_percent"))
                .or_else(|| item.get("percentRemaining"))
                .and_then(|v| v.as_f64());
            let reset = item
                .get("resetText")
                .or_else(|| item.get("reset_text"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            meters.push(QuotaMeter::time_limit(label, rem, reset, None));
        }
    } else if let Some(rem) = json.get("remainingPercent").and_then(|v| v.as_f64()) {
        meters.push(QuotaMeter::time_limit(section_id, Some(rem), None, None));
    }
    meters
}
