# iOS 1.0 验证记录与验收清单

## 已执行（Linux / 无 Apple SDK）

- `bash scripts/test-core.sh`：可移植 Swift 核心断言，包括歌词/备份/歌曲模型、LX inited/capability/index、HTTP 签名 URL 与私网拒绝、同曲匹配、Android analytics JSON 字段与类型。
- `node tests/LXBridgeTests.js`：假宿主 LX 协议，异步回调、取消、二进制、计时器、加密接口、HTTP/HTTPS 字符串回归。
- `swiftc -frontend -parse`：全量 Swift 源文件语法解析（不是 iOS SDK 类型检查）。
- `plutil -lint`：Xcode 工程、Info.plist、PrivacyInfo.xcprivacy 格式验证。
- `bash -n`：构建脚本语法检查；GitHub workflow 结构检查。

所有测试使用离线 fixture；未请求真实第三方音频，也未向正式统计服务写入数据。

## GitHub Actions 必须完成

工作流 `build-ios.yml` 使用官方 `xcode-27` runner，选择已安装的稳定 Xcode 27.x，执行：
1. Swift 核心和 Node 协议测试。
2. macOS JavaScriptCore / Security / CommonCrypto 真实原生离线 smoke test。
3. 全量 iOS Simulator SDK 编译与 arm64 真机 Release 构建。
4. IPA 归档，检查版本 1.0、最低 iOS 16.0、Bundle ID、资源、后台音频声明及 SHA-256。
5. 手动签名模式验证合法证书和描述文件，`codesign --verify` 检查。

本地没有 Xcode，因此未执行第 2–5 步。以新 commit 的 Actions 日志为准，不能保证第一次 SDK 类型检查无错误。

## 真机验收（iOS 16、17、18、26.0、26.1+、27.x）

- iPhone 小屏、横屏、iPad：系统 tab bar、搜索栏，原生滚动收缩与 inline/expanded mini player；检查无 track 时空附件、键盘、页面 push/pop、字号、深色、减少动态效果及 VoiceOver。旧系统不应出现新系统 API 调用崩溃。
- 音源：导入已授权的 HTTPS JS；标准 inited 无 status、音质/平台声明、云端索引失败保留缓存；确认启用云端自动解析，禁用后不再执行未导入的云脚本。
- 播放：授权 HTTP CDN、HTTPS CDN、带 `%2B`/`%2F`/`%3D` 签名参数的 URL；验证不改写、过期链接重试、无效 URL 错误、网络切换、前后台播放、锁屏、耳机拔出、暂停、seek、队列、歌词与封面；不使用无播放权的内容。
- Android 同曲匹配：不同歌手、时长缺失、live/remix 等拒绝，成功播放后才记忆优选平台。
- 统计：按 `ANALYTICS.md` 的测试环境清单验证，与 Android 记录逐字段比较；正式服务端联调前检查 PHP 是否能接受 iOS 值。
- 回归：原有目录、搜索、榜单、歌单、音乐库、收藏、备份、Files 导入、分享和本地播放统计。
- 安装：使用签名 IPA 在描述文件包含的测试设备中验证；unsigned IPA 不可直接在普通 iPhone 安装。

原 Android 端功能不等同于 iOS 公共 API 的全部能力。已知不完全对等项目及仍需联调的服务见 `MIGRATION.md`。
