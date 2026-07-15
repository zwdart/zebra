# Icon Generator

从 SVG 文件生成各平台标准应用图标。

**跨平台支持**: Windows / macOS / Linux

## 前置条件

- Rust 工具链 (已安装)
- SVG 图标文件 (建议 512x512 或更大，带透明背景)

## 使用方法

### Windows

```bash
# 构建
cd packer && cargo build --release --bin icon-gen

# 生成图标
packer\target\release\icon-gen.exe assets\icon.svg

# 或使用快捷脚本
gen-icons.bat assets\icon.svg
```

### macOS / Linux

```bash
# 构建
cd packer && cargo build --release --bin icon-gen

# 生成图标
./packer/target/release/icon-gen assets/icon.svg

# 或使用快捷脚本
chmod +x gen-icons.sh
./gen-icons.sh assets/icon.svg
```

### 使用 Make (macOS/Linux)

```bash
cd packer

# 构建
make release

# 生成图标
make gen-icons SVG_FILE=../assets/icon.svg
```

### 指定输出目录

```bash
# 生成到其他目录
./packer/target/release/icon-gen assets/icon.svg --output-dir /path/to/output
```

## 生成的文件

### Android (5 个文件)
```
android/app/src/main/res/
├── mipmap-mdpi/ic_launcher.png      (48x48)
├── mipmap-hdpi/ic_launcher.png      (72x72)
├── mipmap-xhdpi/ic_launcher.png     (96x96)
├── mipmap-xxhdpi/ic_launcher.png    (144x144)
└── mipmap-xxxhdpi/ic_launcher.png   (192x192)
```

### iOS (15 个文件)
```
ios/Runner/Assets.xcassets/AppIcon.appiconset/
├── Icon-App-20x20@{1,2,3}x.png
├── Icon-App-29x29@{1,2,3}x.png
├── Icon-App-40x40@{1,2,3}x.png
├── Icon-App-60x60@{2,3}x.png
├── Icon-App-76x76@{1,2}x.png
├── Icon-App-83.5x83.5@2x.png
└── Icon-App-1024x1024@1x.png
```

### macOS (7 个文件)
```
macos/Runner/Assets.xcassets/AppIcon.appiconset/
├── app_icon_16.png   (16x16)
├── app_icon_32.png   (32x32)
├── app_icon_64.png   (64x64)
├── app_icon_128.png  (128x128)
├── app_icon_256.png  (256x256)
├── app_icon_512.png  (512x512)
└── app_icon_1024.png (1024x1024)
```

### Windows (2 个文件)
```
windows/runner/resources/
├── app_icon.ico      (含 16/24/32/48/64/128/256px)
└── StoreLogo.png     (50x50)
```

### Linux (9 个文件)
```
linux/icons/
├── icon_16.png ~ icon_1024.png
```

## SVG 建议

- 尺寸: 至少 512x512，推荐 1024x1024
- 格式: SVG 1.1，使用 `viewBox`
- 背景: 透明 (工具会自动填充透明背景)
- 文字: 建议转为路径，避免字体缺失问题

## 常见问题

**Q: 字体显示不正确?**
A: SVG 中的文字需要转换为路径 (在 Illustrator/Inkscape 中执行"转曲")。

**Q: 想重新生成?**
A: 直接再次运行命令即可覆盖旧文件。

**Q: 图标边缘有锯齿?**
A: 确保 SVG 源文件足够大 (1024x1024)，工具会从高分辨率渲染后缩放。



---启动运行zebra-api服务---
```
# 3. 上传服务文件
scp packer/zebra-api.service root@your-server:/etc/systemd/system/zebra-api.service
# 4. 启动并设置开机自启
sudo systemctl daemon-reload
sudo systemctl enable --now zebra-api
# 5. 查看状态
sudo systemctl status zebra-api
# 6. 查看日志
sudo journalctl -u zebra-api -f
服务文件路径 /etc/systemd/system/zebra-api.service，服务名 zebra-api。
```