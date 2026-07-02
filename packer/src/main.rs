#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bin_reader;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const APP_NAME: &str = "zebra";
const EMBEDDED_DATA: &[u8] = include_bytes!("../target/data.bin");

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
    let current = format!("{}-{}", reader.files.len(), reader.exe);
    stored.trim() != current.trim()
}

fn write_version(dir: &Path, reader: &bin_reader::BinaryReader) {
    let _ = fs::write(dir.join(".version"), format!("{}-{}", reader.files.len(), reader.exe));
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
    Some(dir.join(&reader.exe))
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

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let force = args.contains(&"--extract".to_string());

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
