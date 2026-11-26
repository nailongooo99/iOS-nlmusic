# 奶龙音乐 · iOS 1.0

**Nailong Music for iPhone / iPad — 原生 Swift 源码开发版**

根据上传的 `NailongMusic-3.0-Technical-Upgrade.zip` 为主项目，
以 `CurrentMusicX-main.zip` 和 `lx-music-mobile-master (1).zip` 为协议和体验参考，
重新实现 iOS 客户端。不是将 Android APK、Kotlin、Compose 或 React Native 封装为 iOS。
不是已经实机验证的全功能等价移植，也不包含任何保证可用的免费音乐音源。

| 项目 | 配置 |
|---|---|
| 名称 | 奶龙音乐 |
| iOS 版本 | 1.0 (Marketing version) |
| 本地构建号 | 1；Actions 使用运行编号 |
| Bundle ID | `com.nailong.music.ios`（可在 GitHub Variables 中自定义） |
| Deployment target | iOS / iPadOS 16.0 |
| 构建 SDK | Xcode 27（CI 优先选择已安装的稳定 27.x） |
| 架构 | SwiftUI、NavigationStack、TabView、ObservableObject、Foundation、AVFoundation、MediaPlayer、JavaScriptCore |
| 依赖 | 无 SwiftPM/CocoaPods 第三方依赖；应用无需 Node、Gradle 或 Android SDK |
| 视觉 | iOS 26/27 原生 Liquid Glass；旧系统原生 Material；分组浮动底栏；复用安卓品牌图标 |
| 构建产物 | `.ipa` 与 SHA-256 校验；无签名与合法签名分开 |

## 1. 目录

- `NailongMusic.xcodeproj`：直接双击打开的共享 Xcode 工程，已提交 scheme。
- `NailongMusic/Core`：平台/歌曲/歌单/备份模型、歌词解析、播放模式。
- `NailongMusic/Services`：目录适配、LX UserApi v2、音源管理、音乐库、AVPlayer 播放。
- `NailongMusic/UI`：首页、歌单、搜索、我的、设置、全屏播放器、唱片墙。
- `NailongMusic/Resources`：图标、隐私清单、第三方声明。
- `.github/workflows/build-ios.yml`：CI，编译模拟器及设备、打包 IPA。
- `scripts/`：本地核心测试、打包与签名脚本。
- `examples/authorized-resolver/`：可选自有授权音频服务的接口示例，不是全网音源服务。
- `docs/MIGRATION.md`：与 Android 3.0 的功能对应及未实现项目。
- `docs/TESTING.md`：验证事实与真机验收。

## 2. GitHub Actions：不需要自己的 Mac

1. 创建 GitHub 仓库（建议先设为 Private），解压本项目 ZIP。
2. 上传**项目目录内部所有内容**到仓库根目录，包括隐藏的 `.github`，不是只上传 ZIP。
   在电脑上可使用：
   ```bash
   git init
   git add .
   git commit -m "feat(ios): initial native Nailong Music 1.0"
   git branch -M main
   git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
   git push -u origin main
   ```
3. 打开仓库 **Actions → Build Nailong Music iOS 1.0**。推送 main/master 或 PR 自动触发
   无签名构建；也可 **Run workflow**，选择 `unsigned`。
4. 构建成功后，进入对应 workflow run，在 **Artifacts** 下载产物压缩包并解压。
   `NailongMusic-iOS-1.0-unsigned.ipa` 是用于编译验证和后续合法签名的归档文件，
   **不是可直接安装到普通 iPhone 的 IPA**。
5. Xcode 27 的部署范围包含 iOS 16，但 Apple 当前的 Xcode 27 Device Support /
   Simulator 范围起于 iOS 17；因此 iOS 16 真机验证要使用实际 iOS 16 设备，
   或适当的旧版本 Xcode 环境（旧 SDK 不认识 glassEffect；本项目以 Xcode 27 为编译工具链）。

### 签名（可安装到已注册的设备）

普通 iOS 设备必须接受 Apple 有效的代码签名与描述文件。
需先在 Apple Developer 账户为你拥有的 App ID 和测试设备 UDID 创建对应签名材料。
不要上传私人密钥到仓库。

在 **Settings → Secrets and variables → Actions** 创建 Repository secrets：

| Secret | 内容 |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | 含私钥的 Apple Development 或 Apple Distribution `.p12` 的单行 Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `APPLE_PROVISIONING_PROFILE_BASE64` | 与证书、设备和精确 Bundle ID 匹配的 `.mobileprovision` 的单行 Base64 |

如你的已注册 App ID 不同，创建 Repository variable `IOS_BUNDLE_ID`，填写实际 Bundle ID；
否则采用 `com.nailong.music.ios`。Team ID、Profile UUID 与名称从描述文件读取。

macOS / Linux 生成 Base64（不要把输出提交到 Git）：

```bash
base64 < certificate.p12 | tr -d '\n'
base64 < profile.mobileprovision | tr -d '\n'
```

在 Actions → Run workflow 选择：

- `development`：Apple Development 证书 + 开发描述文件，设备已注册，按系统提示开启开发者模式。
- `ad-hoc`：Apple Distribution 证书 + Ad Hoc 描述文件，测试设备已注册。

CI 先校验描述文件、构建 archive、使用 Xcode exportArchive 输出签名 IPA，并进行 codesign 校验。
将 IPA 解压自 Actions 下载的 artifact ZIP 后，使用 Apple 支持的设备安装工具或合法测试分发方式，
在描述文件所列设备上安装。描述文件、签名过期或设备未注册会失败。
本工作流没有配置 App Store Connect/TestFlight 自动上传；没有证书和描述文件不可能保证安装成功。

### Mac 本地开发

使用 Xcode 27 打开 `NailongMusic.xcodeproj`，选择 scheme `NailongMusic`。
模拟器选择任意可用 iOS 版本；真机需设置 Signing & Capabilities 中的 Team 和唯一 Bundle ID。

```bash
bash scripts/test-core.sh
xcodebuild -project NailongMusic.xcodeproj -scheme NailongMusic \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
bash scripts/build-ipa.sh unsigned
```

如 Xcode 新版 runner 名称变化，请以 GitHub 官方 runner 列表修改 `runs-on: xcode-27`。
私有仓库消耗 Actions macOS 配额；若工作流排队或不可用，请查看实际账户的权限与配额。

## 3. LX 音源、本地播放及云索引

打开「设置 → 音源与网络 → LX 音源管理」，选择本地 `.js` 或粘贴 HTTPS 脚本地址。
先读取脚本和元数据，确认信任后才执行初始化。成功的源默认启用，失败的源保留为禁用并显示原因。
在编辑模式拖动调整优先级；可重新检测、禁用、删除和更新。已有健康音源更新失败时保留旧脚本。
LX 使用系统 JavaScriptCore、CryptoKit、CommonCrypto、Security 和 URLSession，不需要 WebView、
React Native 或其他 JavaScript 运行时；播放仍由 AVPlayer 完成。

兼容 LX UserApi v2 `lx.on`、`lx.send`、`lx.request`、`currentScriptInfo`、`setTimeout`、
`clearTimeout`、四档音质声明、字节转换、MD5、AES-128-CBC/ECB、RSA 公钥加密及随机字节。
解析按已启用源顺序和音质向下回退，失败冷却、超时、取消及旧地址过滤与播放器联动。
五平台目录补充 LX `types`、`_types`、`interval` 等元数据和酷狗的各音质哈希（仅在平台返回时保存）。
JSON 授权音源保留为可选后备，不再替代 LX。

云索引默认沿用 Android `https://www.nailong.link/nlmusic/yinyuan.md`，
支持 Markdown 或纯文本 HTTPS `.js` 地址，刷新失败保留上次缓存。可以改索引地址、刷新和逐条导入。
为了避免执行未确认的外部代码，云端索引不会后台批量自动执行，也不会自动安装更新。
脚本下载与本地库均限大小，网络请求经原生 HTTPS 代理。仅允许公网域名 443 端口，
拒绝明文 HTTP 和已知非公网地址，重定向重新检查地址，跨域不传递 Cookie/Authorization。
用户须确认脚本来源可信，且拥有音频与服务使用权限。本项目不附带第三方播放脚本。

JavaScriptCore 是进程内执行环境，并非完整的恶意代码隔离沙箱；公开 API 不能强制终止同步无限循环。
引擎限制队列、并发网络、请求次数和等待时间；超时取消等待和网络任务，但若脚本无限循环，
共享 JS 执行队列可能仍阻塞直至重新启动 App。DNS 检查是防御措施，不是 DNS pinning。
原 LX 允许的 HTTP 地址、非标准端口、桌面专用 API、zlib、局域网服务和非标准脚本可能不兼容。
不要导入不可信来源，不应将初始化成功视为播放成功或安全认证。

本地音乐仍可从 Files 导入；也可导入自己拥有的 HTTPS 音频链接。
可选 JSON 服务协议和示例见 `examples/authorized-resolver/`；LX 不需要此服务。
更详细的功能、交互与待验收事项见 `docs/LX_AND_CHROME.md`。

## 4. Android 迁移

在 Android 奶龙音乐导出 `nailong.music.library` JSON v1–v4，在 iOS 设置 → 备份管理 → 导入。
确认后才覆盖现有音乐库。备份文件大小限 32 MiB，检查格式与关键字段，拒绝未知版本。
支持便携的歌曲信息、收藏歌单、搜索历史、统计、优选源引用和本地歌单内的在线曲目。
不复制音频、Android SAF `content://` 授权、私有临时地址、脚本或服务配置；LX 脚本请在 iOS 单独导入。
iOS 的本地文件与自有 URL 记录不写入 Android 兼容备份，避免旧安卓无法识别 `.local` 平台。
请保留本地音频原始文件。Android 导入后的本地文件引用不会自动恢复音频。
未经过实际 Android → iOS → Android 真机往返验收。

## 5. 安全与发布

- 应用使用系统 ATS HTTPS 校验，不绕过 DRM、会员、授权或 TLS。
- 未实现 Android 的默认访问统计上传；听歌统计只保存在本机。目录、歌词、封面和
  解析音源请求会向对应服务发送必要的歌曲元数据，配置服务时应了解其隐私政策。
- 使用上传项目中原有的奶龙图标；保留相关开源许可证和第三方声明。
- Android APK 的强制更新与下载安装流程不适用于 iOS，未复用安卓版本号或 APK 下载地址。
- 应用内在线公告和法律文档仍用上传项目的网站地址；当前未联调，失败时显示错误/重试。
- 正式公开分发前请自行核查第三方接口、品牌与内容权利、隐私清单及 App Review 指南。
- 当前环境无 macOS/iOS SDK，无法在这里验证 Xcode 编译、签名、真实设备、线上接口或帧率；
  CI 提供首次真实编译的路径。不要把 Swift 语法解析当成 Xcode 类型检查结果。

参考（官方）：[Xcode SDKs and system requirements](https://developer.apple.com/xcode/system-requirements/)、
[GitHub hosted runner labels](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)、
[Apple device distribution](https://developer.apple.com/documentation/xcode/distributing-apps-to-your-development-devices)。

## 首次构建修复（版本仍为 1.0）

已修复自建歌单添加歌曲时的 Swift 独占访问编译错误，并增加回归检查。CI 更新 checkout 至 v6，构建失败时将编译错误提取到 Summary，并保留无签名编译日志 artifact。更新源码后请重新提交 main，勿对旧 commit 仅执行 Re-run jobs。

## LX 与浮动底栏更新（版本 1.0 不变）

新增 7 个 Swift 文件和 LX 协议资源；51 项可移植核心检查和 Node 假宿主协议测试已通过。Actions 另执行真实 Apple JavaScriptCore 原生离线测试及完整模拟器/设备构建。Linux 中不能运行 Xcode 或实际 iOS UI；目前尚无完整 iOS 构建、签名、真机体验或第三方音源联调结论。
