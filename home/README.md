# Zebra SSH 官网首页

## 页面结构

| 区块 | 行号 | 说明 |
|------|------|------|
| Navbar | 45-118 | 固定顶部导航栏，含 logo、四个锚点链接、下载按钮、移动端汉堡菜单 |
| Header | 145-179 | 首屏大标题 + tagline，居中布局 |
| Features | 201-289 | 6 张功能卡片（SSH终端/SFTP/监控/进程/清理/跨平台），点击展开详情 |
| Usage | 291-383 | 4 步使用说明，点击展开操作指南 |
| Download | 385-469 | 5 个平台下载区（Android/iOS/Windows/macOS/Linux），未发布的按钮置灰 |
| Sponsors | 471-526 | 赞助商展示（一间小店/GitHub/官网/联系） |
| Footer | 528-555 | 版权 + 底部链接 |
| JS | 1019-1063 | 菜单切换、卡片折叠、滚动高亮导航 |

## 资源路径

- 图标: `./assets/icons/icon.png`（favicon + 页面 logo）
- APK 下载: `./assets/bundles/*.apk`
- 外部依赖: Font Awesome 6.4.0 CDN

## 样式方案

- 纯内联 CSS，CSS 变量定义主题色（蓝色系 `#7dd3fc` / `#38bdf8`）
- 深色背景 `#0c1f35`，响应式断点 768px

## 修改指南

- 改文案: 直接编辑对应 `<h3>` / `<p>` 标签
- 加新功能卡片: 复制 `.feature-card` 块，修改内容即可
- 改颜色: 修改 `:root` 下的 CSS 变量
- 加新平台下载: 复制 `.platform-group` 块，替换为可用链接（去掉 `disabled` 类）
- 改赞助商: 修改 `.sponsor-card` 的 href 和文案
