/**
 * icon_gen.rs
 *
 * 从 SVG 文件生成所有平台的标准应用图标
 * 支持: Android / iOS / macOS / Windows / Linux
 *
 * 用法:
 *   icon-gen <svg-file>
 *   icon-gen <svg-file> --output-dir <dir>
 */

use std::fs;
use std::path::{Path, PathBuf};
use clap::Parser;

/// 从 SVG 生成各平台标准图标
#[derive(Parser)]
#[command(name = "icon-gen", about = "Generate platform-specific app icons from SVG")]
struct Args {
    /// SVG 文件路径
    svg: PathBuf,

    /// 输出根目录 (默认为项目根目录)
    #[arg(short, long)]
    output_dir: Option<PathBuf>,
}

/// 获取项目根目录
fn get_project_root() -> PathBuf {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir.parent().unwrap().to_path_buf()
}

/// 渲染 SVG 到指定尺寸的 PNG
fn render_svg(svg_content: &str, width: u32, height: u32) -> Result<Vec<u8>, String> {
    let opt = usvg::Options::default();

    let rtree = usvg::Tree::from_str(svg_content, &opt)
        .map_err(|e| format!("Failed to parse SVG: {}", e))?;

    let svg_size = rtree.size();

    let pixmap_size = tiny_skia::IntSize::from_wh(width, height)
        .ok_or_else(|| format!("Invalid size: {}x{}", width, height))?;

    let mut pixmap = tiny_skia::Pixmap::new(pixmap_size.width(), pixmap_size.height())
        .ok_or_else(|| format!("Failed to create pixmap {}x{}", width, height))?;

    pixmap.fill(tiny_skia::Color::TRANSPARENT);

    let scale_x = width as f32 / svg_size.width() as f32;
    let scale_y = height as f32 / svg_size.height() as f32;

    resvg::render(&rtree, usvg::Transform::from_scale(scale_x, scale_y), &mut pixmap.as_mut());

    pixmap.encode_png()
        .map_err(|e| format!("Failed to encode PNG: {}", e))
}

/// 保存 PNG 文件
fn save_png(path: &Path, data: &[u8], size: u32) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create dir {}: {}", parent.display(), e))?;
    }
    fs::write(path, data)
        .map_err(|e| format!("Failed to write {}: {}", path.display(), e))?;
    println!("  {:?}  ({}x{})", path.file_name().unwrap(), size, size);
    Ok(())
}

// ─── ICO 编码 (手动实现，无需额外依赖) ──────────────────────────────────────

struct IcoEntry {
    width: u32,
    height: u32,
    png_data: Vec<u8>,
}

fn encode_ico(entries: &[IcoEntry]) -> Vec<u8> {
    let num_images = entries.len() as u16;
    let header_size = 6usize;
    let dir_entry_size = 16usize;

    // 计算总大小
    let mut total_size = header_size + dir_entry_size * num_images as usize;
    for entry in entries {
        total_size += entry.png_data.len();
    }

    let mut buf = Vec::with_capacity(total_size);

    // ICO 文件头 (6 bytes)
    buf.extend_from_slice(&[0, 0]);          // reserved
    buf.extend_from_slice(&[1, 0]);          // type: 1 = ICO
    buf.extend_from_slice(&num_images.to_le_bytes());

    // 计算数据偏移
    let mut data_offset = header_size + dir_entry_size * num_images as usize;

    // 目录项
    for entry in entries {
        let w = if entry.width >= 256 { 0u8 } else { entry.width as u8 };
        let h = if entry.height >= 256 { 0u8 } else { entry.height as u8 };
        buf.push(w);
        buf.push(h);
        buf.push(0);      // color palette
        buf.push(0);      // reserved
        buf.extend_from_slice(&[1, 0]); // color planes
        buf.extend_from_slice(&[32, 0]); // bits per pixel
        buf.extend_from_slice(&(entry.png_data.len() as u32).to_le_bytes());
        buf.extend_from_slice(&(data_offset as u32).to_le_bytes());
        data_offset += entry.png_data.len();
    }

    // PNG 数据
    for entry in entries {
        buf.extend_from_slice(&entry.png_data);
    }

    buf
}

// ─── Android ──────────────────────────────────────────────────────────────────

struct AndroidIcon {
    dir: &'static str,
    size: u32,
}

const ANDROID_ICONS: &[AndroidIcon] = &[
    AndroidIcon { dir: "mipmap-mdpi",    size: 48  },
    AndroidIcon { dir: "mipmap-hdpi",    size: 72  },
    AndroidIcon { dir: "mipmap-xhdpi",   size: 96  },
    AndroidIcon { dir: "mipmap-xxhdpi",  size: 144 },
    AndroidIcon { dir: "mipmap-xxxhdpi", size: 192 },
];

const ANDROID_PATH: &str = "android/app/src/main/res";

fn generate_android(svg: &str, root: &Path) -> Result<(), String> {
    println!("[Android]");
    let base = root.join(ANDROID_PATH);

    for icon in ANDROID_ICONS {
        let dir = base.join(icon.dir);
        let path = dir.join("ic_launcher.png");
        let data = render_svg(svg, icon.size, icon.size)?;
        save_png(&path, &data, icon.size)?;
    }
    Ok(())
}

// ─── iOS ──────────────────────────────────────────────────────────────────────

struct IosIcon {
    file: &'static str,
    w: u32,
    h: u32,
}

const IOS_ICONS: &[IosIcon] = &[
    IosIcon { file: "Icon-App-20x20@1x.png",       w: 20,  h: 20  },
    IosIcon { file: "Icon-App-20x20@2x.png",       w: 40,  h: 40  },
    IosIcon { file: "Icon-App-20x20@3x.png",       w: 60,  h: 60  },
    IosIcon { file: "Icon-App-29x29@1x.png",       w: 29,  h: 29  },
    IosIcon { file: "Icon-App-29x29@2x.png",       w: 58,  h: 58  },
    IosIcon { file: "Icon-App-29x29@3x.png",       w: 87,  h: 87  },
    IosIcon { file: "Icon-App-40x40@1x.png",       w: 40,  h: 40  },
    IosIcon { file: "Icon-App-40x40@2x.png",       w: 80,  h: 80  },
    IosIcon { file: "Icon-App-40x40@3x.png",       w: 120, h: 120 },
    IosIcon { file: "Icon-App-60x60@2x.png",       w: 120, h: 120 },
    IosIcon { file: "Icon-App-60x60@3x.png",       w: 180, h: 180 },
    IosIcon { file: "Icon-App-76x76@1x.png",       w: 76,  h: 76  },
    IosIcon { file: "Icon-App-76x76@2x.png",       w: 152, h: 152 },
    IosIcon { file: "Icon-App-83.5x83.5@2x.png",   w: 167, h: 167 },
    IosIcon { file: "Icon-App-1024x1024@1x.png",   w: 1024, h: 1024 },
];

const IOS_PATH: &str = "ios/Runner/Assets.xcassets/AppIcon.appiconset";

fn generate_ios(svg: &str, root: &Path) -> Result<(), String> {
    println!("[iOS]");
    let dir = root.join(IOS_PATH);
    fs::create_dir_all(&dir).ok();

    for icon in IOS_ICONS {
        let path = dir.join(icon.file);
        let data = render_svg(svg, icon.w, icon.h)?;
        save_png(&path, &data, icon.w)?;
    }
    Ok(())
}

// ─── macOS ────────────────────────────────────────────────────────────────────

struct MacosIcon {
    file: &'static str,
    size: u32,
}

const MACOS_ICONS: &[MacosIcon] = &[
    MacosIcon { file: "app_icon_16.png",   size: 16  },
    MacosIcon { file: "app_icon_32.png",   size: 32  },
    MacosIcon { file: "app_icon_64.png",   size: 64  },
    MacosIcon { file: "app_icon_128.png",  size: 128 },
    MacosIcon { file: "app_icon_256.png",  size: 256 },
    MacosIcon { file: "app_icon_512.png",  size: 512 },
    MacosIcon { file: "app_icon_1024.png", size: 1024 },
];

const MACOS_PATH: &str = "macos/Runner/Assets.xcassets/AppIcon.appiconset";

fn generate_macos(svg: &str, root: &Path) -> Result<(), String> {
    println!("[macOS]");
    let dir = root.join(MACOS_PATH);
    fs::create_dir_all(&dir).ok();

    for icon in MACOS_ICONS {
        let path = dir.join(icon.file);
        let data = render_svg(svg, icon.size, icon.size)?;
        save_png(&path, &data, icon.size)?;
    }
    Ok(())
}

// ─── Windows ──────────────────────────────────────────────────────────────────

const WINDOWS_ICO_SIZES: &[u32] = &[16, 24, 32, 48, 64, 128, 256];
const WINDOWS_STORE_LOGO_SIZE: u32 = 50;
const WINDOWS_PATH: &str = "windows/runner/resources";

fn generate_windows(svg: &str, root: &Path) -> Result<(), String> {
    println!("[Windows]");
    let dir = root.join(WINDOWS_PATH);
    fs::create_dir_all(&dir).ok();

    // 生成各尺寸 PNG 并编码为 ICO
    let mut entries = Vec::new();
    for &size in WINDOWS_ICO_SIZES {
        let png_data = render_svg(svg, size, size)?;
        entries.push(IcoEntry {
            width: size,
            height: size,
            png_data,
        });
    }

    let ico_data = encode_ico(&entries);
    let ico_path = dir.join("app_icon.ico");
    fs::write(&ico_path, &ico_data)
        .map_err(|e| format!("Failed to write ICO: {}", e))?;
    println!("  app_icon.ico  (sizes: {:?})", WINDOWS_ICO_SIZES);

    // StoreLogo
    let store_data = render_svg(svg, WINDOWS_STORE_LOGO_SIZE, WINDOWS_STORE_LOGO_SIZE)?;
    let store_path = dir.join("StoreLogo.png");
    save_png(&store_path, &store_data, WINDOWS_STORE_LOGO_SIZE)?;

    Ok(())
}

// ─── Linux ────────────────────────────────────────────────────────────────────

struct LinuxIcon {
    file: &'static str,
    size: u32,
}

const LINUX_ICONS: &[LinuxIcon] = &[
    LinuxIcon { file: "icon_16.png",   size: 16  },
    LinuxIcon { file: "icon_24.png",   size: 24  },
    LinuxIcon { file: "icon_32.png",   size: 32  },
    LinuxIcon { file: "icon_48.png",   size: 48  },
    LinuxIcon { file: "icon_64.png",   size: 64  },
    LinuxIcon { file: "icon_128.png",  size: 128 },
    LinuxIcon { file: "icon_256.png",  size: 256 },
    LinuxIcon { file: "icon_512.png",  size: 512 },
    LinuxIcon { file: "icon_1024.png", size: 1024 },
];

const LINUX_PATH: &str = "linux/icons";

fn generate_linux(svg: &str, root: &Path) -> Result<(), String> {
    println!("[Linux]");
    let dir = root.join(LINUX_PATH);
    fs::create_dir_all(&dir).ok();

    for icon in LINUX_ICONS {
        let path = dir.join(icon.file);
        let data = render_svg(svg, icon.size, icon.size)?;
        save_png(&path, &data, icon.size)?;
    }
    Ok(())
}

// ─── Main ─────────────────────────────────────────────────────────────────────

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    if !args.svg.exists() {
        eprintln!("Error: SVG file not found: {}", args.svg.display());
        std::process::exit(1);
    }

    let svg_content = fs::read_to_string(&args.svg)
        .map_err(|e| format!("Failed to read SVG: {}", e))?;

    let root = args.output_dir.unwrap_or_else(get_project_root);

    println!("\nIcon Generator");
    println!("  SVG source: {}", args.svg.display());
    println!("  Output root: {}\n", root.display());

    generate_android(&svg_content, &root)?;
    generate_ios(&svg_content, &root)?;
    generate_macos(&svg_content, &root)?;
    generate_windows(&svg_content, &root)?;
    generate_linux(&svg_content, &root)?;

    println!("\nDone! All platform icons generated.\n");
    Ok(())
}
