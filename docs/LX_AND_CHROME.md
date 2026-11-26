# LX 与悬浮底栏 · iOS 1.0 更新

## 使用 LX

路径：设置 → 音源与网络 → LX 音源管理。
- 本地导入：使用 iOS 文件选择器选择 UTF-8 `.js` 文件，最大 1 MiB。
- URL 导入：粘贴公网 HTTPS 脚本地址，下载后展示作者、版本、名称和来源。
- 确认信任并导入检测：运行初始化，读取标准 `lx.send(EVENT_NAMES.inited, {sources: ...})`。
  不要求 `status: true`；如明确 `status: false` 或无有效 musicUrl 能力，则标记失败。
- 通过初始化后启用、显示平台和四档音质；失败源禁用，可重新检测。
- 编辑可删除或拖动调整优先级；链接源可重新下载更新，失败时保留已通过初始化的旧源。
- 云端索引：默认沿用用户上传的 Android `RemoteSources.kt` 中的 yinyuan.md。
  兼容 Markdown 与纯文本 `.js` 链接，去重，最大 512 条；刷新失败保留原缓存。
  点击一条链接后按相同确认流程导入，云索引不批量自动执行脚本。

## 实现说明

`LXModels.swift`：协议声明、元数据、音质顺序、云索引解析、歌曲字段。
`LXRuntime.swift`：单独串行 JavaScriptCore 工作队列，初始化、事件、回调、定时器、超时与取消。
`lx-user-api-ios.js`：标准 `lx` 全局对象，UserApi v2 的 `on`/`send`/`request`/`utils`。
`LXCrypto.swift`：原生 MD5、AES-128、RSA 与系统随机字节。
`LXNetwork.swift`：原生 URLSession HTTPS 请求代理，限制请求大小、响应、并发、重定向与域名。
`LXSourceStore.swift`：应用私有目录音源库、启用、排序、更新、检测、云端索引缓存。
`Catalog.swift`：保留五平台 LX 所需的歌曲字段与已知音质哈希。
`Player.swift` / `SourceService.swift`：播放解析优先 LX，之后可选 JSON，最终由 AVPlayer 播放。

兼容的是 v2 移动端 musicUrl 主协议，不保证所有私人、混淆或桌面专用脚本兼容。
支持标准 JSON、表单、文本 multipart、二进制请求响应与取消接口，拒绝 HTTP、非 443 端口和本地网络。
未提供 zlib、Node API、系统文件、设备身份、通用 WebView/DOM、自动执行远端更新。
脚本执行是进程内 JavaScriptCore，不是进程级安全沙箱；仅运行用户信任的脚本。
单次初始化最长约 8 秒，解析每音质最长约 10 秒；LX 解析总预算 45 秒，DNS 检查及清理可能有额外短暂延迟。
超时取消等待及网络任务，不能保证停止 JavaScriptCore 的同步无限循环，需重新启动 App。
源能力检测只检验脚本声明，不能保证远端服务、版权、地区、音质或歌曲播放成功。
没有提供用于绕过授权的第三方音源脚本或免费音源。

## 底栏交互

在根 TabView 中保留五个 NavigationStack，不更改四个主页面及搜索的导航状态。
隐藏系统默认 tab bar，使用原生 SwiftUI 组成两个独立悬浮胶囊：
- 左： 首页 / 歌单 / 我的 / 设置。
- 右： 独立搜索按钮，保留选中状态。
- 迷你播放条置于两组底栏上方，播放、暂停、封面、标题、进度与横向切歌手势仍在。
- 向上滑动页面内容达到阈值时，底栏和迷你播放条下移、变窄并减高；
  紧凑状态主菜单仅图标、播放条保留标题、进度和播放暂停。
- 反向滑动、回到顶部（iOS 18+）、切换菜单或关闭键盘恢复展开。
- iOS 18+ 用 `onScrollGeometryChange`，iOS 16/17 使用同时手势兼容。
- iOS 26+ 使用原生 `glassEffect`，旧版使用 Material。
- 遵循系统减少动态效果；键盘出现时隐藏底栏，避免覆盖搜索输入。

这些是源码实现说明；当前 Linux 环境未运行 iOS UI，真实动画效果、列表滚动事件、
键盘、iPad 适配、不同系统的布局需要实际设备验收。

## 测试

`bash scripts/test-core.sh`：核心模型与 LX 格式测试。
`node tests/LXBridgeTests.js`：离线假宿主桥接测试（仅开发测试，不是 App 运行依赖）。
`bash scripts/test-lx-native.sh`：macOS 上的 Apple 原生 JSC / Crypto smoke test。
GitHub Actions 保持 Xcode 27、iOS 16.0 部署目标与 IPA 签名流程，并新增真实原生 LX 离线测试。
失败时 Summary 与诊断 artifact 可用于定位问题。当前环境未运行 macOS/Xcode/真实网络联调。

版本保持 1.0、Bundle ID 与原工程不变。此前已修复的歌单重叠访问错误仍保留修复。
