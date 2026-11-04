# 本机验证记录

日期：2026-11-04。环境：Apple Silicon Mac，Swift 6.4.2，Xcode 27，Booted iPhone 18 Pro Max / iOS 27.2。

## 已通过

- Swift debug / release 构建；App bundle 本地 ad-hoc 签名、codesign --verify --strict、Info.plist lint。
- 4 项 XCTest：Booted/可用设备解析与错误、精确 LocalStorage 容器发现、媒体路由及中文重名/内容校验/符号链接拒绝、子进程失败与超时。
- 正式 ImportService 真实导入：PNG 照片、中文文本、含子目录及空文件的文件夹、重名文本。文件内容通过 SHA256 校验，重名生成 (2) 副本。
- 实际 App GUI 自动列出 iPhone 18 Pro Max / iOS 27.2，默认选中设备。
- NSOpenPanel 选择「界面验证.txt」导入，GUI 显示逐项完成与「已复制到文件存储」。
- 实际 Device Hub / iOS Files UI：我的 iPhone → SimDrop 中可见「界面验证」、示例文件夹、测试文本及 (2) 副本。
- 实际深色主窗口检查：布局和文本无截断，设备、模式、拖入区和结果区可用。

## 验证边界

- Finder 跨 App 的真实鼠标拖拽未完成自动化验收：桌面工具在窗口菜单/跨窗口坐标控制上出现错误。源码使用 SwiftUI 原生 dropDestination(for: URL.self)，与文件选择复用同一批量导入入口；需用户实际试拖确认。
- 未验证多台同时 Booted、运行中关闭目标设备、大批量视频及浅色界面。设备过滤、路由与错误处理有逻辑覆盖，不能等同这些真实场景已经验收。
- 普通文件依赖 Files LocalStorage 的兼容方案，并非稳定公开导入 API。App 报复制成功不保证所有未来 runtime 的 Files UI 都即时刷新。
- 仅完成本机运行签名，未做 Developer ID 公证或对外发布。

## 已修复的验收问题

- async 入口占据 MainActor 导致 GUI 设备不刷新：改为同步 App 主入口。
- rsync 文件夹隐式嵌套导致校验失败：明确 source/ 到预建 staging/ 的复制语义，并重新真实验证。

## SimVoya 更名验证（2026-11-04）

- Swift Package、product、target、测试模块与源码目录统一更名为 SimVoya；Bundle ID=com.charles.simvoya。
- release 构建及 codesign --verify --strict 通过；4项 XCTest 全部通过，0失败。
- 实际启动新 App：窗口、菜单显示 SimVoya，自动识别 iPhone 18 Pro Max / iOS 27.2；导入目标提示为文件 App / SimVoya。
- 正式 ImportService 导入自建 SimVoya-rename-check.txt 成功，新目标为 File Provider Storage/SimVoya，已通过内容校验。此次未重新操作 Files UI 检查新目录。
- dist 仅保留 SimVoya.app；旧 SimDrop.app 移至系统临时目录备份。历史模拟器导入内容保留，不迁移或删除。

## 开源文档截图验证（2026-11-04）

- 确认工具链 Xcode 27.2（27B52）。
- 通过实际 App 文件选择入口导入自身图标 SimVoya-icon.png 及专门创建的 Welcome.txt；GUI 显示照片导入及文件存储复制完成。
- 将主窗口与导入结果实际截图保存至 docs/screenshots，并用于 README。未将 Finder 实拖或 Files UI 刷新标记为本轮已验证。
