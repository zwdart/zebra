<#
.SYNOPSIS
    从 SVG 源文件生成各平台标准图标
.DESCRIPTION
    支持 Windows / macOS / Linux / Android / iOS
    需要以下任一工具: Inkscape, ImageMagick (magick), rsvg-convert
.PARAMETER SvgPath
    SVG 源文件路径
.PARAMETER OutDir
    输出根目录 (默认: 项目根目录)
.EXAMPLE
    .\gen_icons.ps1 -SvgPath logo.svg
    .\gen_icons.ps1 -SvgPath logo.svg -OutDir D:\myproject
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SvgPath,
    [string]$OutDir = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

# ── 检测 SVG 转换工具 ──────────────────────────────────────
function Find-SvgTool {
    $candidates = @(
        @{ Name = "inkscape"; Args = { param($svg, $w, $o) "inkscape" "-w $w" "-h $w" "`"$svg`"" "-o `"$o`"" } },
        @{ Name = "magick";   Args = { param($svg, $w, $o) "magick" "`"$svg`"" "-resize ${w}x${w}" "`"$o`"" } },
        @{ Name = "convert";  Args = { param($svg, $w, $o) "convert" "`"$svg`"" "-resize ${w}x${w}" "`"$o`"" } },
        @{ Name = "rsvg-convert"; Args = { param($svg, $w, $o) "rsvg-convert" "-w $w" "-h $w" "`"$svg`"" "-o `"$o`"" } }
    )
    foreach ($c in $candidates) {
        $path = Get-Command $c.Name -ErrorAction SilentlyContinue
        if ($path) { return $c }
    }
    return $null
}

function Render-Png {
    param([string]$Svg, [int]$Size, [string]$OutFile)
    $dir = Split-Path $OutFile -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tool = $script:SvgTool
    $args = & $tool.Args $Svg $Size $OutFile
    Write-Host "  ${Size}x${Size} -> $OutFile"
    & $tool.Name @($args.Split(' ') | ForEach-Object { $_ -replace '^"|"$', '' })
    if ($LASTEXITCODE -ne 0) { throw "SVG conversion failed for ${Size}x${Size}" }
}

$SvgTool = Find-SvgTool
if (!$SvgTool) {
    Write-Host ""
    Write-Host "[ERROR] 未找到 SVG 转换工具，请安装以下任一:" -ForegroundColor Red
    Write-Host "  1. Inkscape  : https://inkscape.org/release/"
    Write-Host "  2. ImageMagick: https://imagemagick.org/script/download.php"
    Write-Host "  3. librsvg   : https://gitlab.gnome.org/GNOME/librsvg/-/releases"
    exit 1
}
Write-Host "使用工具: $($SvgTool.Name)" -ForegroundColor Green
Write-Host ""

$SvgPath = (Resolve-Path $SvgPath).Path

# ── 1. Windows (.ico) ─────────────────────────────────────
Write-Host "=== Windows (.ico) ===" -ForegroundColor Cyan
$icoDir = Join-Path $OutDir "windows\runner\resources"
$icoTmp = Join-Path $env:TEMP "icon_build_ico"
if (Test-Path $icoTmp) { Remove-Item $icoTmp -Recurse -Force }
New-Item -ItemType Directory -Path $icoTmp -Force | Out-Null

$icoSizes = @(16, 32, 48, 64, 128, 256)
$icoPngs = @()
foreach ($s in $icoSizes) {
    $png = Join-Path $icoTmp "icon_${s}.png"
    Render-Png $SvgPath $s $png
    $icoPngs += $png
}

# 合并为 .ico (用 ImageMagick 或 fallback 到 PowerShell)
$icoFile = Join-Path $icoDir "app_icon.ico"
$magick = Get-Command "magick" -ErrorAction SilentlyContinue
$convert = Get-Command "convert" -ErrorAction SilentlyContinue
if ($magick) {
    $inputStr = ($icoPngs | ForEach-Object { "`"$_`"" }) -join " "
    Invoke-Expression "magick $inputStr `"$icoFile`""
} elseif ($convert) {
    $inputStr = ($icoPngs | ForEach-Object { "`"$_`"" }) -join " "
    Invoke-Expression "convert $inputStr `"$icoFile`""
} else {
    # 用 .NET 手动拼装 ICO 文件
    Write-Host "  (无 ImageMagick, 用 .NET 生成 ICO)"
    $fs = [System.IO.File]::Create($icoFile)
    $bw = [System.IO.BinaryWriter]::new($fs)

    # ICO header: reserved(2) + type(2) + count(2)
    $bw.Write([uint16]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]$icoPngs.Count)

    $pngDataList = @()
    $offset = 6 + ($icoPngs.Count * 16)
    foreach ($png in $icoPngs) {
        $bytes = [System.IO.File]::ReadAllBytes($png)
        $pngDataList += ,$bytes

        # 读取 PNG 尺寸 (IHDR: offset 16..23)
        $w = [BitConverter]::ToUInt32($bytes, 16)
        $h = [BitConverter]::ToUInt32($bytes, 20)
        $w = [int]$w
        $h = [int]$h
        # PNG 存储时 height 含 mask, 但实际不需要

        $bw.Write([byte]$(if ($w -ge 256) { 0 } else { $w }))
        $bw.Write([byte]$(if ($h -ge 256) { 0 } else { $h }))
        $bw.Write([byte]0)      # color count
        $bw.Write([byte]0)      # reserved
        $bw.Write([uint16]1)    # color planes
        $bw.Write([uint16]32)   # bits per pixel
        $bw.Write([uint32]$bytes.Length)
        $bw.Write([uint32]$offset)
        $offset += $bytes.Length
    }
    foreach ($data in $pngDataList) {
        $bw.Write($data)
    }
    $bw.Close()
    $fs.Close()
}
Write-Host "  -> $icoFile" -ForegroundColor Green

# ── 2. macOS (.app bundle PNGs + .iconset) ─────────────────
Write-Host ""
Write-Host "=== macOS (iconset + build_mac.sh 生成 .icns) ===" -ForegroundColor Cyan
$macIconSrc = Join-Path $OutDir "macos\Runner\Assets.xcassets\AppIcon.appiconset"
$macPngSizes = @{
    "app_icon_16.png"    = 16
    "app_icon_32.png"    = 32
    "app_icon_64.png"    = 64
    "app_icon_128.png"   = 128
    "app_icon_256.png"   = 256
    "app_icon_512.png"   = 512
    "app_icon_1024.png"  = 1024
}
foreach ($entry in $macPngSizes.GetEnumerator()) {
    $out = Join-Path $macIconSrc $entry.Key
    Render-Png $SvgPath $entry.Value $out
}

# macOS iconset (供 iconutil 使用)
$macIconset = Join-Path $OutDir "packer\macos_iconset"
if (Test-Path $macIconset) { Remove-Item $macIconset -Recurse -Force }
New-Item -ItemType Directory -Path $macIconset -Force | Out-Null
$iconsetMap = @{
    "icon_16x16.png"       = 16
    "icon_16x16@2x.png"    = 32
    "icon_32x32.png"       = 32
    "icon_32x32@2x.png"    = 64
    "icon_128x128.png"     = 128
    "icon_128x128@2x.png"  = 256
    "icon_256x256.png"     = 256
    "icon_256x256@2x.png"  = 512
    "icon_512x512.png"     = 512
    "icon_512x512@2x.png"  = 1024
}
foreach ($entry in $iconsetMap.GetEnumerator()) {
    $out = Join-Path $macIconset $entry.Key
    Render-Png $SvgPath $entry.Value $out
}
Write-Host "  iconset -> $macIconset" -ForegroundColor Green
Write-Host "  (macOS 上执行: iconutil -c icns $macIconset -o macos_icon.icns)" -ForegroundColor DarkGray

# ── 3. Linux (PNGs) ───────────────────────────────────────
Write-Host ""
Write-Host "=== Linux (PNGs) ===" -ForegroundColor Cyan
$linuxIconDir = Join-Path $OutDir "packer\linux_icons"
if (Test-Path $linuxIconDir) { Remove-Item $linuxIconDir -Recurse -Force }
New-Item -ItemType Directory -Path $linuxIconDir -Force | Out-Null
foreach ($s in @(16, 32, 48, 64, 128, 256, 512)) {
    Render-Png $SvgPath $s (Join-Path $linuxIconDir "zebra_${s}x${s}.png")
}
Write-Host "  -> $linuxIconDir" -ForegroundColor Green

# ── 4. Android (mipmap) ───────────────────────────────────
Write-Host ""
Write-Host "=== Android (mipmap) ===" -ForegroundColor Cyan
$androidRes = Join-Path $OutDir "android\app\src\main\res"
$androidSizes = @{
    "mipmap-mdpi"    = 48
    "mipmap-hdpi"    = 72
    "mipmap-xhdpi"   = 96
    "mipmap-xxhdpi"  = 144
    "mipmap-xxxhdpi" = 192
}
foreach ($entry in $androidSizes.GetEnumerator()) {
    $dir = Join-Path $androidRes $entry.Key
    Render-Png $SvgPath $entry.Value (Join-Path $dir "ic_launcher.png")
}

# Adaptive icon (foreground 512x512 + 纯色 background)
$adaptiveDir = Join-Path $androidRes "mipmap-anydpi-v26"
if (!(Test-Path $adaptiveDir)) { New-Item -ItemType Directory -Path $adaptiveDir -Force | Out-Null }
Render-Png $SvgPath 512 (Join-Path $adaptiveDir "ic_launcher_foreground.png")
Write-Host "  adaptive icon -> $adaptiveDir" -ForegroundColor Green

# 生成 adaptive icon XML
$adaptiveXml = @"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"@
$adaptiveXml | Out-File -FilePath (Join-Path $adaptiveDir "ic_launcher.xml") -Encoding utf8
Write-Host "  ic_launcher.xml -> $adaptiveDir" -ForegroundColor Green

# 确保 colors.xml 有 ic_launcher_background
$colorsXml = Join-Path $OutDir "android\app\src\main\res\values\colors.xml"
if (Test-Path $colorsXml) {
    $content = Get-Content $colorsXml -Raw
    if ($content -notmatch "ic_launcher_background") {
        $content = $content -replace "</resources>", "    <color name=""ic_launcher_background"">#FFFFFF</color>`n</resources>"
        $content | Out-File -FilePath $colorsXml -Encoding utf8
        Write-Host "  colors.xml 已添加 ic_launcher_background" -ForegroundColor Green
    }
}

# ── 5. iOS (AppIcon.appiconset) ────────────────────────────
Write-Host ""
Write-Host "=== iOS (AppIcon.appiconset) ===" -ForegroundColor Cyan
$iosIconDir = Join-Path $OutDir "ios\Runner\Assets.xcassets\AppIcon.appiconset"
$iosSizes = @{
    "Icon-App-20x20@1x.png"                = 20
    "Icon-App-20x20@2x.png"                = 40
    "Icon-App-20x20@3x.png"                = 60
    "Icon-App-29x29@1x.png"                = 29
    "Icon-App-29x29@2x.png"                = 58
    "Icon-App-29x29@3x.png"                = 87
    "Icon-App-40x40@1x.png"                = 40
    "Icon-App-40x40@2x.png"                = 80
    "Icon-App-40x40@3x.png"                = 120
    "Icon-App-60x60@2x.png"                = 120
    "Icon-App-60x60@3x.png"                = 180
    "Icon-App-76x76@1x.png"                = 76
    "Icon-App-76x76@2x.png"                = 152
    "Icon-App-83.5x83.5@2x.png"            = 167
    "Icon-App-1024x1024@1x.png"            = 1024
}
foreach ($entry in $iosSizes.GetEnumerator()) {
    Render-Png $SvgPath $entry.Value (Join-Path $iosIconDir $entry.Key)
}
Write-Host "  -> $iosIconDir" -ForegroundColor Green

# ── 清理临时文件 ──────────────────────────────────────────
Remove-Item $icoTmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  所有平台图标已生成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Windows : windows\runner\resources\app_icon.ico"
Write-Host "  macOS   : macos\Runner\...\AppIcon.appiconset\ + packer\macos_iconset\"
Write-Host "  Linux   : packer\linux_icons\"
Write-Host "  Android : android\app\src\main\res\mipmap-*\"
Write-Host "  iOS     : ios\Runner\...\AppIcon.appiconset\"
Write-Host ""
Write-Host "macOS .icns 需在 macOS 上执行:" -ForegroundColor DarkGray
Write-Host "  iconutil -c icns packer/macos_iconset -o packer/macos_icon.icns" -ForegroundColor DarkGray
