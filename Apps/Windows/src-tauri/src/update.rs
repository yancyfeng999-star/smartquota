//! Free **manual** update check via public GitHub Releases.
//! No auto-download / silent install.

use serde::Serialize;

const GITHUB_OWNER: &str = "yancyfeng999-star";
const GITHUB_REPO: &str = "smartquota";
const API_URL: &str =
    "https://api.github.com/repos/yancyfeng999-star/smartquota/releases?per_page=30";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateCheckResult {
    pub current_version: String,
    /// `upToDate` | `available` | `error`
    pub status: String,
    pub latest_version: Option<String>,
    pub message: String,
    pub open_url: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
struct GhRelease {
    tag_name: String,
    html_url: String,
    draft: bool,
    prerelease: bool,
    assets: Vec<GhAsset>,
}

#[derive(Debug, serde::Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct SemVer {
    major: u32,
    minor: u32,
    patch: u32,
}

impl SemVer {
    fn parse(raw: &str) -> Option<Self> {
        let mut s = raw.trim().to_string();
        if s.is_empty() {
            return None;
        }
        let lower = s.to_ascii_lowercase();
        if lower.starts_with("mac-") {
            s = s[4..].to_string();
        }
        if s.to_ascii_lowercase().starts_with("windows-") {
            s = s["windows-".len()..].to_string();
        }
        if s.to_ascii_lowercase().starts_with('v') {
            s = s[1..].to_string();
        }
        if let Some(idx) = s.find(['-', '+']) {
            s.truncate(idx);
        }
        let parts: Vec<&str> = s.split('.').collect();
        if parts.len() < 2 || parts.len() > 3 {
            return None;
        }
        let major = parts[0].parse().ok()?;
        let minor = parts[1].parse().ok()?;
        let patch = if parts.len() == 3 {
            parts[2].parse().unwrap_or(0)
        } else {
            0
        };
        Some(Self {
            major,
            minor,
            patch,
        })
    }

    fn display(&self) -> String {
        format!("{}.{}.{}", self.major, self.minor, self.patch)
    }
}

fn is_windows_candidate(tag: &str, assets: &[GhAsset]) -> bool {
    let lower = tag.to_ascii_lowercase();
    if lower.starts_with("windows") {
        return true;
    }
    assets.iter().any(|a| {
        let n = a.name.to_ascii_lowercase();
        n.ends_with(".exe") || n.ends_with(".msi")
    })
}

fn preferred_windows_download(assets: &[GhAsset]) -> Option<String> {
    let mut ranked: Vec<(u8, String)> = Vec::new();
    for a in assets {
        let n = a.name.to_ascii_lowercase();
        let score = if n.ends_with(".exe") {
            if n.contains("setup") || n.contains("smartquota") {
                0
            } else {
                1
            }
        } else if n.ends_with(".msi") {
            2
        } else {
            continue;
        };
        ranked.push((score, a.browser_download_url.clone()));
    }
    ranked.sort_by_key(|(s, _)| *s);
    ranked.into_iter().next().map(|(_, u)| u)
}

fn current_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

pub async fn check_for_windows_update() -> UpdateCheckResult {
    let current_s = current_app_version();
    let Some(current) = SemVer::parse(&current_s) else {
        return UpdateCheckResult {
            current_version: current_s,
            status: "error".into(),
            latest_version: None,
            message: "无法识别当前版本号".into(),
            open_url: None,
        };
    };

    let client = match reqwest::Client::builder()
        .user_agent("SmartQuota-Windows (manual-update-check)")
        .timeout(std::time::Duration::from_secs(20))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            return UpdateCheckResult {
                current_version: current.display(),
                status: "error".into(),
                latest_version: None,
                message: format!("网络客户端错误：{e}"),
                open_url: None,
            };
        }
    };

    let resp = match client
        .get(API_URL)
        .header("Accept", "application/vnd.github+json")
        .header("X-GitHub-Api-Version", "2022-11-28")
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return UpdateCheckResult {
                current_version: current.display(),
                status: "error".into(),
                latest_version: None,
                message: format!("检查失败：{e}"),
                open_url: None,
            };
        }
    };

    if !resp.status().is_success() {
        return UpdateCheckResult {
            current_version: current.display(),
            status: "error".into(),
            latest_version: None,
            message: format!("检查失败：HTTP {}", resp.status()),
            open_url: None,
        };
    }

    let releases: Vec<GhRelease> = match resp.json().await {
        Ok(v) => v,
        Err(e) => {
            return UpdateCheckResult {
                current_version: current.display(),
                status: "error".into(),
                latest_version: None,
                message: format!("解析失败：{e}"),
                open_url: None,
            };
        }
    };

    let mut best: Option<(SemVer, String)> = None;
    for r in releases {
        if r.draft || r.prerelease {
            continue;
        }
        if !is_windows_candidate(&r.tag_name, &r.assets) {
            continue;
        }
        let Some(ver) = SemVer::parse(&r.tag_name) else {
            continue;
        };
        let open = preferred_windows_download(&r.assets).unwrap_or_else(|| r.html_url.clone());
        match &best {
            None => best = Some((ver, open)),
            Some((bv, _)) if ver > *bv => best = Some((ver, open)),
            _ => {}
        }
    }

    let Some((latest, open_url)) = best else {
        return UpdateCheckResult {
            current_version: current.display(),
            status: "error".into(),
            latest_version: None,
            message: "未找到可用的 Windows 发布包".into(),
            open_url: Some(format!(
                "https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}/releases"
            )),
        };
    };

    if latest > current {
        UpdateCheckResult {
            current_version: current.display(),
            status: "available".into(),
            latest_version: Some(latest.display()),
            message: format!(
                "发现新版本 {}（当前 {}）",
                latest.display(),
                current.display()
            ),
            open_url: Some(open_url),
        }
    } else {
        UpdateCheckResult {
            current_version: current.display(),
            status: "upToDate".into(),
            latest_version: Some(latest.display()),
            message: format!("已是最新（{}）", current.display()),
            open_url: None,
        }
    }
}
