fn main() {
    // Windows: 嵌入 .ico 图标到 .exe
    #[cfg(windows)]
    {
        let icon_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("windows/runner/resources/app_icon.ico");

        if icon_path.exists() {
            let mut res = winres::WindowsResource::new();
            res.set_icon(icon_path.to_str().unwrap());
            res.compile().unwrap();
        }
    }

    // macOS: 图标通过 .app bundle 设置 (build_mac.sh 处理)
    // Linux: 图标通过 .desktop 文件设置 (build_linux.sh 处理)
}
