mod account_cache;
mod accounts;
mod alerts;
mod catalog;
mod detect;
mod extensions;
mod models;
mod paths;
mod probes;
mod secrets;
mod settings;
mod update;

use alerts::{collect_alerts, show_system_notification};
use chrono::Local;
use detect::DetectItem;
use models::{session_weekly_from_meters, status_from_meters, ProbeTestResult, QuotaCard, SnapshotPayload};
use settings::AppSettings;
use accounts::{AccountDiscoveryEvent, MultiAccountState};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, Runtime, WebviewWindow,
};

#[tauri::command]
async fn get_usage_snapshot() -> SnapshotPayload {
    let mut settings = AppSettings::load();
    let order = settings.resolved_order();
    let mut cards = Vec::new();

    // Parallel-ish: sequential still fine; spawn futures for enabled only
    let mut handles = Vec::new();
    for id in order {
        let s = settings.clone();
        handles.push(async move { probes::probe_provider(&id, &s).await });
    }
    for h in handles {
        cards.push(h.await);
    }

    // Extensions
    if settings.extensions_enabled {
        for (id, name, res) in extensions::probe_all_extensions().await {
            match res {
                Ok(meters) => {
                    let (session, weekly) = session_weekly_from_meters(&meters);
                    cards.push(QuotaCard {
                        provider_id: id,
                        display_name: name,
                        status: status_from_meters(&meters),
                        session_remaining_percent: session,
                        weekly_remaining_percent: weekly,
                        meters,
                        plan_label: String::new(),
                        detail: "用户扩展脚本".into(),
                        enabled: true,
                        source_mode: "auto".into(),
                        is_core: false,
                        account_id: None,
                        account_email: None,
                        account_label: None,
                        account_state: None,
                    });
                }
                Err(msg) => {
                    cards.push(QuotaCard {
                        provider_id: id,
                        display_name: name,
                        status: "error".into(),
                        session_remaining_percent: None,
                        weekly_remaining_percent: None,
                        meters: vec![],
                        plan_label: String::new(),
                        detail: msg,
                        enabled: true,
                        source_mode: "auto".into(),
                        is_core: false,
                        account_id: None,
                        account_email: None,
                        account_label: None,
                        account_state: None,
                    });
                }
            }
        }
    }

    let alerts = collect_alerts(&cards, &mut settings);
    if !alerts.is_empty() {
        let _ = settings.save();
        for a in &alerts {
            show_system_notification("智额 · 额度提醒", &a.message);
        }
    }
    SnapshotPayload {
        updated_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        cards,
        alerts,
    }
}

#[tauri::command]
async fn test_provider(provider_id: String) -> ProbeTestResult {
    let settings = AppSettings::load();
    let card = probes::probe_provider(&provider_id, &settings).await;
    if card.status == "error" || card.status == "disabled" || card.status == "setup" {
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

#[tauri::command]
fn get_catalog() -> Vec<serde_json::Value> {
    catalog::DISPLAY_ORDER
        .iter()
        .map(|id| {
            serde_json::json!({
                "id": id,
                "name": catalog::display_name(id),
                "isCore": catalog::is_core(id),
                "defaultEnabled": catalog::default_enabled(id),
            })
        })
        .collect()
}

#[tauri::command]
fn detect_credentials() -> Vec<DetectItem> {
    detect::detect_all(&AppSettings::load())
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
fn set_provider_order(order: Vec<String>) -> Result<AppSettings, String> {
    let mut s = AppSettings::load();
    s.provider_order = order;
    s.save()?;
    Ok(s)
}

#[tauri::command]
fn set_window_pinned(app: tauri::AppHandle, pinned: bool) -> Result<AppSettings, String> {
    let mut s = AppSettings::load();
    s.window_pinned = pinned;
    s.save()?;
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_always_on_top(pinned);
    }
    Ok(s)
}

#[tauri::command]
fn list_extensions() -> Vec<extensions::ExtensionInfo> {
    extensions::list_extensions()
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
fn set_kimi_api_key(api_key: String) -> Result<(), String> {
    secrets::set_secret(secrets::KIMI_API_KEY, api_key.trim())
}
#[tauri::command]
fn has_kimi_api_key() -> bool {
    secrets::get_secret(secrets::KIMI_API_KEY).is_some()
}
#[tauri::command]
fn clear_kimi_api_key() -> Result<(), String> {
    secrets::delete_secret(secrets::KIMI_API_KEY)
}

#[tauri::command]
fn set_github_token(token: String) -> Result<(), String> {
    secrets::set_secret(secrets::GITHUB_TOKEN, token.trim())
}
#[tauri::command]
fn has_github_token() -> bool {
    secrets::get_secret(secrets::GITHUB_TOKEN).is_some()
}
#[tauri::command]
fn clear_github_token() -> Result<(), String> {
    secrets::delete_secret(secrets::GITHUB_TOKEN)
}

#[tauri::command]
fn set_provider_api_key(provider_id: String, api_key: String) -> Result<(), String> {
    secrets::set_secret(&secrets::provider_key_account(&provider_id), api_key.trim())
}
#[tauri::command]
fn has_provider_api_key(provider_id: String) -> bool {
    secrets::get_secret(&secrets::provider_key_account(&provider_id)).is_some()
}
#[tauri::command]
fn clear_provider_api_key(provider_id: String) -> Result<(), String> {
    secrets::delete_secret(&secrets::provider_key_account(&provider_id))
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
        "kimiConfig": paths::kimi_config_path().display().to_string(),
        "geminiOauth": paths::gemini_oauth_path().display().to_string(),
        "cursorDb": paths::cursor_state_db_path().display().to_string(),
        "claudeJson": paths::claude_json_path().display().to_string(),
        "extensions": extensions::extensions_dir().display().to_string(),
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
    open_path(&paths::ensure_config_dir().map_err(|e| e.to_string())?)
}
#[tauri::command]
fn open_logs_dir() -> Result<(), String> {
    open_path(&paths::ensure_logs_dir().map_err(|e| e.to_string())?)
}
#[tauri::command]
fn open_extensions_folder() -> Result<(), String> {
    let dir = extensions::extensions_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    open_path(&dir)
}

#[tauri::command]
async fn check_for_update() -> update::UpdateCheckResult {
    update::check_for_windows_update().await
}

#[tauri::command]
fn open_external_url(url: String) -> Result<(), String> {
    let url = url.trim();
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err("invalid url".into());
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/C", "start", "", url])
            .spawn()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(url)
            .spawn()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Err("unsupported OS".into())
    }
}

// ---- Account Tauri commands ----

#[tauri::command]
fn get_account_states() -> MultiAccountState {
    MultiAccountState::load()
}

#[tauri::command]
fn get_pending_accounts(provider_id: String) -> Vec<accounts::ProviderAccountState> {
    let state = MultiAccountState::load();
    state
        .coordinator(&provider_id)
        .map(|c| c.pending_accounts().into_iter().cloned().collect())
        .unwrap_or_default()
}

#[tauri::command]
fn confirm_account(provider_id: String, account_id: String) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::Confirm {
        account_id: account_id.clone(),
    });
    state.save()?;
    Ok(state)
}

#[tauri::command]
fn ignore_account(provider_id: String, account_id: String) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::Ignore {
        account_id: account_id.clone(),
    });
    state.save()?;
    Ok(state)
}

#[tauri::command]
fn sign_out_account(provider_id: String, account_id: String) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::SignOut {
        account_id: account_id.clone(),
    });
    state.save()?;
    Ok(state)
}

#[tauri::command]
fn select_account(provider_id: String, account_id: String) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::Select {
        account_id: account_id.clone(),
    });
    state.save()?;
    Ok(state)
}

#[tauri::command]
fn delete_account(provider_id: String, account_id: String) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::Delete {
        account_id: account_id.clone(),
    });
    // Also clean up cache and secrets
    let cache = account_cache::AccountSnapshotCache::new();
    cache.delete(&account_id);
    let _ = secrets::delete_account_secret(&provider_id, &account_id, "api_key");
    state.save()?;
    Ok(state)
}

#[tauri::command]
fn ingest_account_snapshot(
    provider_id: String,
    email: Option<String>,
    is_interactive: bool,
) -> Result<MultiAccountState, String> {
    let mut state = MultiAccountState::load();
    let coord = state.coordinator_mut(&provider_id);
    coord.process(AccountDiscoveryEvent::Ingest {
        email,
        is_interactive,
    });
    state.save()?;
    Ok(state)
}

fn show_main_window<R: Runtime>(app: &tauri::AppHandle<R>) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn apply_pin(window: &WebviewWindow, pinned: bool) {
    let _ = window.set_always_on_top(pinned);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = paths::ensure_config_dir();
    let _ = paths::ensure_logs_dir();
    let _ = std::fs::create_dir_all(extensions::extensions_dir());

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_usage_snapshot,
            test_provider,
            get_settings,
            get_catalog,
            save_settings,
            detect_credentials,
            set_provider_enabled,
            set_plan_label,
            set_provider_order,
            set_window_pinned,
            list_extensions,
            set_minimax_region,
            set_minimax_api_key,
            has_minimax_api_key,
            clear_minimax_api_key,
            set_kimi_api_key,
            has_kimi_api_key,
            clear_kimi_api_key,
            set_github_token,
            has_github_token,
            clear_github_token,
            set_provider_api_key,
            has_provider_api_key,
            clear_provider_api_key,
            get_paths,
            open_config_folder,
            open_logs_dir,
            open_extensions_folder,
            check_for_update,
            open_external_url,
            get_account_states,
            get_pending_accounts,
            confirm_account,
            ignore_account,
            sign_out_account,
            select_account,
            delete_account,
            ingest_account_snapshot,
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

            let settings = AppSettings::load();
            if let Some(window) = app.get_webview_window("main") {
                apply_pin(&window, settings.window_pinned);
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
