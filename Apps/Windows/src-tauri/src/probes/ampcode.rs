//! AmpCode — `amp usage --no-color` (Mac AmpCodeUsageProbe).

use crate::models::QuotaMeter;
use regex::Regex;
use std::process::Command;

pub fn available() -> bool {
    which("amp")
}

fn which(bin: &str) -> bool {
    Command::new(bin).arg("--help").output().is_ok()
        || Command::new("where").arg(bin).output().map(|o| o.status.success()).unwrap_or(false)
}

pub async fn probe_ampcode() -> Result<Vec<QuotaMeter>, String> {
    tokio::task::spawn_blocking(|| {
        let output = Command::new("amp")
            .args(["usage", "--no-color"])
            .output()
            .map_err(|_| "未找到 amp CLI（AmpCode）".to_string())?;
        let text = format!(
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        parse_amp_usage(&text)
    })
    .await
    .map_err(|e| e.to_string())?
}

pub fn parse_amp_usage(text: &str) -> Result<Vec<QuotaMeter>, String> {
    let credit_re = Regex::new(
        r"(?i)^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s*/\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining",
    )
    .map_err(|e| e.to_string())?;
    let balance_re =
        Regex::new(r"(?i)^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining").map_err(|e| e.to_string())?;

    let mut meters = Vec::new();
    for line in text.lines().map(|l| l.trim()).filter(|l| !l.is_empty()) {
        if let Some(cap) = credit_re.captures(line) {
            let label = map_label(cap[1].trim());
            let rem: f64 = cap[2].parse().unwrap_or(0.0);
            let total: f64 = cap[3].parse().unwrap_or(0.0);
            if total > 0.0 {
                let pct = (rem / total * 100.0).clamp(0.0, 100.0);
                meters.push(QuotaMeter::model(
                    &label,
                    Some(pct),
                    Some(format!("${rem:.2}/${total:.2}")),
                    None,
                ));
            }
            continue;
        }
        if let Some(cap) = balance_re.captures(line) {
            let label = map_label(cap[1].trim());
            let rem: f64 = cap[2].parse().unwrap_or(0.0);
            meters.push(QuotaMeter::model(
                &label,
                if rem > 0.0 { Some(100.0) } else { Some(0.0) },
                Some(format!("${rem:.2} remaining")),
                None,
            ));
        }
    }
    if meters.is_empty() {
        return Err("amp usage 无有效额度行".into());
    }
    Ok(meters)
}

fn map_label(raw: &str) -> String {
    match raw.to_lowercase().as_str() {
        "amp free" => "Free".into(),
        "individual credits" => "Individual".into(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_sample() {
        let t = "Signed in as a@b.com (x)\nAmp Free: $17.59/$20 remaining (replenishes)\nIndividual credits: $0 remaining\n";
        let m = parse_amp_usage(t).unwrap();
        assert_eq!(m.len(), 2);
    }
}
