// Windows で release ビルド時にコンソール窓を出さない。
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    mmm_lib::run()
}
