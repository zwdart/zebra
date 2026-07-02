use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use clap::Parser;
use walkdir::WalkDir;
use brotli::CompressorWriter;
use md5::{Md5, Digest};

const MAGIC: &[u8] = b"ZEBRA";

#[derive(Parser)]
#[command(name = "zebra-pack", about = "Pack files into a self-extracting exe")]
struct Args {
    #[arg(short, long)]
    folder: String,

    #[arg(short, long, default_value = "zebra.exe")]
    exe: String,

    #[arg(short, long, default_value = "zebra-ssh")]
    name: String,

    #[arg(short, long, default_value = "target")]
    output: String,

    #[arg(short, long, default_value_t = 11)]
    level: u32,
}

struct PackedEntry {
    path: Vec<u8>,
    compressed: Vec<u8>,
    md5: [u8; 16],
}

fn compress_folder(folder: &Path, level: u32) -> Vec<PackedEntry> {
    let mut entries = Vec::new();
    let folder = fs::canonicalize(folder).unwrap();

    for entry in WalkDir::new(&folder).into_iter().filter_map(|e| e.ok()) {
        if !entry.file_type().is_file() {
            continue;
        }
        let full = entry.path();
        let rel = full.strip_prefix(&folder).unwrap();
        let rel_str = rel.to_string_lossy().replace('\\', "/");

        let data = fs::read(full).unwrap();
        let digest = Md5::digest(&data);
        let mut compressed = Vec::new();
        {
            let mut writer = CompressorWriter::new(&mut compressed, 4096, level, 22);
            writer.write_all(&data).unwrap();
        }

        println!("  {} ({} -> {} bytes)", rel_str, data.len(), compressed.len());

        entries.push(PackedEntry {
            path: rel_str.into_bytes(),
            compressed,
            md5: digest.into(),
        });
    }
    entries
}

fn write_data_bin(entries: &[PackedEntry], exe: &str, output: &Path) {
    let mut f = fs::File::create(output).unwrap();
    f.write_all(MAGIC).unwrap();

    for entry in entries {
        let path_len = (entry.path.len() as u32).to_be_bytes();
        f.write_all(&path_len).unwrap();
        f.write_all(&entry.path).unwrap();

        let data_len = (entry.compressed.len() as u32).to_be_bytes();
        f.write_all(&data_len).unwrap();
        f.write_all(&entry.compressed).unwrap();

        f.write_all(&entry.md5).unwrap();
    }

    f.write_all(MAGIC).unwrap();
    let exe_bytes = exe.as_bytes();
    f.write_all(&(exe_bytes.len() as u32).to_be_bytes()).unwrap();
    f.write_all(exe_bytes).unwrap();
}

fn main() {
    let args = Args::parse();
    let folder = PathBuf::from(&args.folder);
    let output = PathBuf::from(&args.output);

    if !folder.is_dir() {
        eprintln!("Folder not found: {}", folder.display());
        std::process::exit(1);
    }

    println!("[1/2] Compressing {} ...", folder.display());
    let entries = compress_folder(&folder, args.level);
    println!("  Total: {} files\n", entries.len());

    let data_bin = output.join("data.bin");
    println!("[2/2] Writing {} ...", data_bin.display());
    write_data_bin(&entries, &args.exe, &data_bin);
    println!("  Size: {} KB\n", fs::metadata(&data_bin).unwrap().len() / 1024);

    println!("Now run: cargo build --release");
    println!("Then rename target/release/zebra.exe to {}.exe", args.name);
}
