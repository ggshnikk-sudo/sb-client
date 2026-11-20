// На десктопе доступны трей и меню, на Android этих модулей в tauri нет,
// поэтому импорты и весь оконный код строго разделены по cfg.
#[cfg(desktop)]
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
#[cfg(desktop)]
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Shortcut, ShortcutState};

#[cfg(mobile)]
use tauri::Manager;

// Стабильные адреса Cloudflare — живут, пока существует аккаунт Cloudflare
#[allow(dead_code)]
pub const SKINBASE_URL: &str = "https://skinbase-dov.pages.dev";
#[allow(dead_code)]
pub const CAPEFORGE_URL: &str = "https://capeforge.i3667563.workers.dev";

// ---------- Desktop (Windows / Linux) ----------

// Показать выбранное сервисное окно, остальное спрятать (сессии живут в фоне)
#[cfg(desktop)]
fn focus_service(app: &tauri::AppHandle, label: &str) {
    for (id, win) in app.webview_windows() {
        if id == "main" {
            continue;
        }
        if id == label {
            let _ = win.show();
            let _ = win.set_focus();
        } else {
            let _ = win.hide();
        }
    }
}

#[cfg(desktop)]
fn toggle_fullscreen_window(win: &tauri::WebviewWindow) {
    let fs = win.is_fullscreen().unwrap_or(false);
    let _ = win.set_fullscreen(!fs);
}

#[cfg(desktop)]
fn toggle_fullscreen(app: &tauri::AppHandle) {
    for (_, win) in app.webview_windows() {
        if win.is_focused().unwrap_or(false) {
            toggle_fullscreen_window(&win);
        }
    }
}

#[cfg(desktop)]
fn setup_desktop(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // Локальная оболочка нужна только на Android — на десктопе закрываем её
    if let Some(shell) = app.get_webview_window("main") {
        let _ = shell.destroy();
    }

    let skinbase = WebviewWindowBuilder::new(
        app,
        "skinbase",
        WebviewUrl::External(SKINBASE_URL.parse().expect("skinbase url")),
    )
    .title("SkinBase")
    .inner_size(1280.0, 860.0)
    .center()
    .resizable(true)
    .fullscreen(false)
    .build()?;

    WebviewWindowBuilder::new(
        app,
        "capeforge",
        WebviewUrl::External(CAPEFORGE_URL.parse().expect("capeforge url")),
    )
    .title("CapeForge")
    .inner_size(1280.0, 860.0)
    .center()
    .resizable(true)
    .fullscreen(false)
    .visible(false)
    .build()?;

    let _ = skinbase.set_focus();

    // F11 — опциональный полноэкранный режим (только когда окно приложения в фокусе)
    let f11 = Shortcut::new(None, Code::F11);
    app.global_shortcut()
        .on_shortcut(f11, |app, _shortcut, event| {
            if event.state() == ShortcutState::Pressed {
                for (_, win) in app.webview_windows() {
                    if win.is_focused().unwrap_or(false) {
                        toggle_fullscreen_window(&win);
                        break;
                    }
                }
            }
        })?;

    // Трей: переключение сервисов, режим окна, выход
    let skinbase_item = MenuItem::with_id(app, "skinbase", "Открыть SkinBase", true, None::<&str>)?;
    let capeforge_item =
        MenuItem::with_id(app, "capeforge", "Открыть CapeForge", true, None::<&str>)?;
    let fullscreen_item = MenuItem::with_id(
        app,
        "fullscreen",
        "Вкл/выкл полный экран (F11)",
        true,
        None::<&str>,
    )?;
    let quit_item = MenuItem::with_id(app, "quit", "Выход", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &skinbase_item,
            &capeforge_item,
            &fullscreen_item,
            &quit_item,
        ],
    )?;

    TrayIconBuilder::with_id("sb-tray")
        .tooltip("SB Client")
        .icon(app.default_window_icon().expect("app icon").clone())
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "skinbase" | "capeforge" => focus_service(app, event.id().as_ref()),
            "fullscreen" => toggle_fullscreen(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    Ok(())
}

// ---------- Android ----------

#[cfg(mobile)]
fn setup_mobile(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // Единственное окно грузит локальную оболочку (ui/).
    // Кнопки в ней — обычные ссылки: WebView уходит на сервис,
    // системная кнопка «Назад» возвращает к оболочке.
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();

    #[cfg(desktop)]
    let builder = builder.plugin(tauri_plugin_global_shortcut::Builder::new().build());

    builder
        .setup(|app| {
            #[cfg(desktop)]
            setup_desktop(app)?;
            #[cfg(mobile)]
            setup_mobile(app)?;
            Ok(())
        })
        .on_window_event(|_window, _event| {
            // Закрытие сервисного окна прячем в трей, чтобы сессии не умирали
            #[cfg(desktop)]
            if let WindowEvent::CloseRequested { api, .. } = _event {
                if _window.label() != "main" {
                    api.prevent_close();
                    let _ = _window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("не удалось запустить SB Client");
}
