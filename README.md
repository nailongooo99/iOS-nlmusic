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
| 架构 | SwiftUI、NavigationStack、TabView、ObservableObject、Foundation、AVFoundation、MediaPlayer |
| 依赖 | 无 SwiftPM/CocoaPods 第三方依赖；无需安装 Node、Gradle 或 Android SDK |
| 视觉 | iOS 26/27 原生 Liquid Glass；旧系统原生 Material；复用安卓品牌图标 |
| 构建产物 | `.ipa` 与 SHA-256 校验；无签名与合法签名分开 |

## 1. 目录

- `NailongMusic.xcodeproj`：直接双击打开的共享 Xcode 工程，已提交 scheme。
- `NailongMusic/Core`：平台/歌曲/歌单/备份模型、歌词解析、播放模式。
- `NailongMusic/Services`：目录适配、授权音源、音乐库、AVPlayer 播放。
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

## 3. 音源及本地播放

首次启动无授权音源，音乐目录可以独立加载。在线歌曲不能凭搜索结果自动获得播放权限。
打开设置 → 音源与网络，添加您有权访问的 HTTPS JSON 服务；可添加多个，并调整优先级。
默认首选 320k，也可以选 128k、FLAC 或高解析 FLAC，依次降级至可用质量。
仅播放服务明确返回的授权 HTTPS 音频 URL，AVPlayer 负责实际解码。返回流格式、内容授权、
区域限制、CDN 签名及网络可用性均由服务和平台决定。HTTP 被拒绝，不关闭 ATS。

请求：

```http
POST /resolve
Content-Type: application/json
```

```json
{
  "platform": "wy",
  "id": "123456",
  "title": "示例歌曲",
  "artist": "示例歌手",
  "quality": "320k",
  "metadata": {"songmid":"123456", "albumId":"123"}
}
```

响应：

```json
{
  "url": "https://your-authorized-media.example/audio/song.mp3",
  "lyrics": "[00:00.00]可选授权歌词"
}
```

`examples/authorized-resolver/resolver.py` 仅按服务运营者自行维护的 URL 白名单映射请求，
不会抓取或解锁任何第三方付费音频。替换 catalog.example.json 的示例数据，在自己的可信
HTTPS 反向代理后运行：

```bash
python3 examples/authorized-resolver/resolver.py --catalog your-catalog.json
```

然后在 App 添加 `https://your-domain.example/resolve`。
没有网络服务时，“我的 → 导入本地音频”可直接从 Files 选择自己拥有的 MP3、AAC、
AVPlayer 所支持的其他文件；也支持导入自己拥有的 HTTPS 音频直链。
系统编解码能力和设备情况仍须实际验证。

Android 的 LX 自定义 JavaScript 云索引、自动下载/运行脚本及 CurrentMusic 网易云
直接解析链**未移植**；本项目不包含 JavaScript 执行器，不直接执行外部下载代码。
CurrentMusic 的线路测速与歌词回退独立实现。若需要沿用旧 LX 源，须另行做受控桥接，
并确认脚本、服务器、内容授权和应用分发合规性；不能仅复制 JS 地址作为 JSON 服务。

## 4. Android 迁移

在 Android 奶龙音乐导出 `nailong.music.library` JSON v1–v4，在 iOS 设置 → 备份管理 → 导入。
确认后才覆盖现有音乐库。备份文件大小限 32 MiB，检查格式与关键字段，拒绝未知版本。
支持便携的歌曲信息、收藏歌单、搜索历史、统计、优选源引用和本地歌单内的在线曲目。
不复制音频、Android SAF `content://` 授权、私有临时地址、脚本或服务配置。
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
