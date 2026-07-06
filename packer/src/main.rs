#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bin_reader;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const APP_NAME: &str = "zebra";
const EMBEDDED_DATA: &[u8] = include_bytes!("../target/data.bin");
const EMBEDDED_ICON: &[u8] = include_bytes!("../../linux/icons/icon_512.png");
const DESKTOP_FILE: &str = "xin.dart.zebra.desktop";

fn data_checksum(data: &[u8]) -> u64 {
    let mut hash: u64 = 14695981039346656037;
    for &byte in data {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    hash
}

fn get_extract_dir() -> PathBuf {
    if let Some(local) = dirs::data_local_dir() {
        local.join(APP_NAME)
    } else {
        PathBuf::from(format!("{}.{}", APP_NAME, std::process::id()))
    }
}

fn needs_extract(dir: &Path, reader: &bin_reader::BinaryReader) -> bool {
    let meta = dir.join(".version");
    if !meta.exists() {
        return true;
    }
    let stored = fs::read_to_string(&meta).unwrap_or_default();
    let checksum = data_checksum(EMBEDDED_DATA);
    let current = format!("{}-{}-{}", reader.files.len(), reader.exe, checksum);
    stored.trim() != current.trim()
}

fn write_version(dir: &Path, reader: &bin_reader::BinaryReader) {
    let checksum = data_checksum(EMBEDDED_DATA);
    let _ = fs::write(dir.join(".version"), format!("{}-{}-{}", reader.files.len(), reader.exe, checksum));
}

fn extract(reader: &bin_reader::BinaryReader, dir: &Path, force: bool) -> Option<PathBuf> {
    if force || needs_extract(dir, reader) {
        println!("Extracting files...");
        let _ = fs::remove_dir_all(dir);
        fs::create_dir_all(dir).ok();

        for file in &reader.files {
            let path = dir.join(&file.path);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).ok();
            }
            fs::write(&path, &file.data).ok();
        }

        write_version(dir, reader);
        println!("Done.");
    }
    let exe_path = dir.join(&reader.exe);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&exe_path, fs::Permissions::from_mode(0o755));
    }
    Some(exe_path)
}

fn launch(exe: &Path, args: Vec<String>) {
    let mut cmd = Command::new(exe);
    cmd.args(&args);
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x00000008);
    }

    if let Err(e) = cmd.spawn() {
        eprintln!("Failed to launch {}: {}", exe.display(), e);
        std::process::exit(1);
    }
}

#[cfg(unix)]
fn do_install() -> bool {
    use std::os::unix::fs::PermissionsExt;

    let local = match dirs::data_local_dir() {
        Some(d) => d,
        None => {
            eprintln!("Cannot determine local data dir");
            return false;
        }
    };
    let bin_dir = local.join("bin");
    let icon_dir = local.join("icons");
    let desktop_dir = local.join("applications");

    let exe_path = match std::env::current_exe() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Cannot determine current executable path: {}", e);
            return false;
        }
    };

    fs::create_dir_all(&bin_dir).ok();
    fs::create_dir_all(&icon_dir).ok();
    fs::create_dir_all(&desktop_dir).ok();

    let target = bin_dir.join(APP_NAME);
    if let Err(e) = fs::copy(&exe_path, &target) {
        eprintln!("Failed to copy binary: {}", e);
        return false;
    }
    fs::set_permissions(&target, fs::Permissions::from_mode(0o755)).ok();

    let icon_dst = icon_dir.join("zebra.png");
    fs::write(&icon_dst, EMBEDDED_ICON).ok();

    let old_desktop = desktop_dir.join("zebra-ssh.desktop");
    fs::remove_file(old_desktop).ok();

    let desktop_content = format!(
        "[Desktop Entry]\n\
         Name=Zebra SSH\n\
         GenericName=SSH Client\n\
         Comment=Zebra SSH Client\n\
         Exec={}\n\
         Icon={}\n\
         Terminal=false\n\
         Type=Application\n\
         StartupWMClass=xin.dart.zebra\n\
         Categories=Network;Utility;\n",
        target.display(),
        icon_dst.display(),
    );
    if let Err(e) = fs::write(desktop_dir.join(DESKTOP_FILE), &desktop_content) {
        eprintln!("Failed to write desktop entry: {}", e);
        return false;
    }

    let _ = Command::new("update-desktop-database").arg(&desktop_dir).status();
    let _ = Command::new("gtk-update-icon-cache").arg(&icon_dir).status();

    println!("Installed successfully!");
    println!("  Binary: {}", target.display());
    println!("  Desktop: {}", desktop_dir.join(DESKTOP_FILE).display());
    true
}

#[cfg(unix)]
fn do_uninstall() {
    let local = dirs::data_local_dir().expect("Cannot determine local data dir");
    let extract_dir = local.join(APP_NAME);

    let items = [
        local.join("bin").join(APP_NAME),
        local.join("icons").join("zebra.png"),
        local.join("applications").join(DESKTOP_FILE),
        local.join("applications").join("zebra-ssh.desktop"),
    ];

    for item in &items {
        if item.exists() {
            fs::remove_file(item).ok();
        }
    }

    if extract_dir.exists() {
        fs::remove_dir_all(&extract_dir).ok();
    }

    let desktop_dir = local.join("applications");
    let icon_dir = local.join("icons");
    let _ = Command::new("update-desktop-database").arg(&desktop_dir).status();
    let _ = Command::new("gtk-update-icon-cache").arg(&icon_dir).status();

    println!("Uninstalled successfully!");
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    #[cfg(unix)]
    {
        if args.contains(&"--uninstall".to_string()) {
            do_uninstall();
            return;
        }
    }

    let force = args.contains(&"--extract".to_string());

    // 未安装时尝试安装，失败也继续启动
    #[cfg(unix)]
    {
        let local = dirs::data_local_dir().unwrap_or_default();
        if !local.join("bin").join(APP_NAME).exists() {
            if !do_install() {
                eprintln!("Install failed, launching directly...");
            }
        }
    }

    let reader = bin_reader::BinaryReader::from_bytes(EMBEDDED_DATA);
    let dir = get_extract_dir();

    if let Some(exe) = extract(&reader, &dir, force) {
        if exe.exists() {
            launch(&exe, args);
        } else {
            eprintln!("Not found: {}", exe.display());
            std::process::exit(1);
        }
    }
}
