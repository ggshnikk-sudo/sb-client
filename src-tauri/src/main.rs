// Не показывать консоль в релизной сборке Windows
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    sb_client_lib::run()
}
