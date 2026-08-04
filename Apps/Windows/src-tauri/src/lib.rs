mod detect;
mod models;
mod paths;
mod probes;
mod secrets;
mod settings;

use chrono::Local;
use detect::DetectItem;
use models::{ProbeTestResult, SnapshotPayload};
use settings::AppSettings;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, Runtime,
};

const PROVIDER_ORDER: &[&str] = &["codex", "minimax", "grok"];

#[tauri::command]
async fn get_usage_snapshot() -> SnapshotPayload {
    let settings = AppSettings::load();
    let mut cards = Vec::new();
    for id in PROVIDER_ORDER {
        cards.push(probes::probe_provider(id, &settings).await);
    }
    SnapshotPayload {
        updated_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        cards,
    }
}

#[tauri::command]
async fn test_provider(provider_id: String) -> ProbeTestResult {
    let settings = AppSettings::load();
    let card = probes::probe_provider(&provider_id, &settings).await;
    if card.status == "error" || card.status == "disabled" {
        ProbeTestResult {
            ok: false,
            message: card.detail,
        }
    } else {
        ProbeTestResult {
            ok: true,
            message: format!("{} · {}", card.status, card.detail),
        }
    }
}

#[tauri::command]
fn get_settings() -> AppSettings {
    AppSettings::load()
}

/// Scan local machine for credentials — never returns secrets, only readiness.
#[tauri::command]
fn detect_credentials() -> Vec<DetectItem> {
    let settings = AppSettings::load();
    detect::detect_all(&settings)
}

#[tauri::command]
fn save_settings(settings: AppSettings) -> Result<(), String> {
    settings.save()
}

#[tauri::command]
fn set_provider_enabled(provider_id: String, enabled: bool) -> Result<AppSettings, String> {
    let mut s = AppSettings::load();
    s.set_enabled(&provider_id, enabled);
    s.save()?;
    Ok(s)
}

#[tauri::command]
fn set_plan_label(provider_id: String, plan_label: String) -> Result<AppSettings, String> {
    let mut s = AppSettings::load();
    s.set_plan_label(&provider_id, plan_label);
    s.save()?;
    Ok(s)
}

#[tauri::command]
fn set_minimax_region(region: String) -> Result<AppSettings, String> {
    let mut s = AppSettings::load();
    s.minimax_region = if region == "international" {
        "international".into()
    } else {
        "china".into()
    };
    s.save()?;
    Ok(s)
}

#[tauri::command]
fn set_minimax_api_key(api_key: String) -> Result<(), String> {
    secrets::set_secret(secrets::MINIMAX_API_KEY, api_key.trim())
}

#[tauri::command]
fn has_minimax_api_key() -> bool {
    secrets::get_secret(secrets::MINIMAX_API_KEY).is_some()
}

#[tauri::command]
fn clear_minimax_api_key() -> Result<(), String> {
    secrets::delete_secret(secrets::MINIMAX_API_KEY)
}

#[tauri::command]
fn get_paths() -> serde_json::Value {
    serde_json::json!({
        "settings": paths::settings_path().display().to_string(),
        "configDir": paths::config_dir().display().to_string(),
        "logs": paths::log_file_path().display().to_string(),
        "codexAuth": paths::codex_auth_path().display().to_string(),
        "grokAuth": paths::grok_auth_path().display().to_string(),
        "minimaxConfig": paths::minimax_config_path().display().to_string(),
    })
}

fn open_path(path: &std::path::Path) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(path)
            .spawn()
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(path)
            .spawn()
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        let _ = path;
        Err("unsupported OS".into())
    }
}

#[tauri::command]
fn open_config_folder() -> Result<(), String> {
    let dir = paths::ensure_config_dir().map_err(|e| e.to_string())?;
    open_path(&dir)
}

#[tauri::command]
fn open_logs_dir() -> Result<(), String> {
    let dir = paths::ensure_logs_dir().map_err(|e| e.to_string())?;
    open_path(&dir)
}

fn show_main_window<R: Runtime>(app: &tauri::AppHandle<R>) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = paths::ensure_config_dir();
    let _ = paths::ensure_logs_dir();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_usage_snapshot,
            test_provider,
            get_settings,
            save_settings,
            detect_credentials,
            set_provider_enabled,
            set_plan_label,
            set_minimax_region,
            set_minimax_api_key,
            has_minimax_api_key,
            clear_minimax_api_key,
            get_paths,
            open_config_folder,
            open_logs_dir,
        ])
        .setup(|app| {
            let quit = MenuItem::with_id(app, "quit", "退出智额", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "打开智额", true, None::<&str>)?;
            let refresh = MenuItem::with_id(app, "refresh", "刷新额度", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &refresh, &quit])?;

            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("智额 · SmartQuota");
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            let _tray = tray
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "show" | "refresh" => show_main_window(app),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        show_main_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // Close to tray instead of quit
            if let Some(window) = app.get_webview_window("main") {
                let window_clone = window.clone();
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = window_clone.hide();
                    }
                });
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running 智额");
}
