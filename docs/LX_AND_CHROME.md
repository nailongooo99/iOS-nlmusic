# iOS 1.0 原生底栏和 LX 音源升级

## 系统组件

- iOS 26.0+：真正的系统 `TabView`、`Tab`、`TabRole.search`、`tabBarMinimizeBehavior(.onScrollDown)`、`tabViewBottomAccessory`。系统负责底栏玻璃材质、搜索分离、滚动收缩及 inline/expanded 附件布局。
- iOS 26.1+ 使用 `isEnabled:` 重载；26.0 使用可用的内容重载。无播放项目时隐藏迷你播放器；26.0 的空附件 safe area 行为须真机验证。
- iOS 16–18：系统 TabView/UITabBar，NavigationStack 与原生控件；mini player 用系统 Material、Button、ProgressView。保留兼容层滚动观察，仅压缩 mini player 的内容，不伪造 Liquid Glass 底栏。
- 播放器仍用 SwiftUI sheet、Slider、Menu、AVPlayer、MPVolumeView、MPRemoteCommandCenter。原有品牌资源、列表、搜索、歌单、设置等保留。
- iPadOS 及横屏采用系统自适应导航，不强制模拟 iPhone 浮动栏。系统选择是否使用 inline/minimization。

## 根因与播放链路

旧 iOS JS bridge 的 `__nlMusicUrl` 只接受 `https://`；`LXProtocol.httpsURL` 和 `LXNetwork.checked` 再次要求 HTTPS/443。
而上传的 Android `lx-user-api-bridge.js`、`UserApiEngine.kt`、`SafeNet.validAudio` 接受公网 HTTP/HTTPS，LX UserApi v2 的 `musicUrl` 返回 URL 字符串。
因此合法签名 HTTP CDN 链接在旧 iOS 会于进入 AVPlayer 前被误拒绝。这是可静态确认的根因之一；未获取实际出错脚本或现场响应，不能认定为唯一原因。

新链路：

1. `Catalog` 保留五平台歌曲 ID、音质数据、时长和各音质 hash，`LXProtocol.musicInfo` 构造协议元数据。
2. 用户已确认的导入脚本优先；可明确启用可信云索引 `yinyuan.md`，按需 HTTPS 下载，保留缓存、限制脚本大小；不运行整个索引。
3. `JavaScriptCore` 初始化标准 `inited.sources`，只尝试 `musicUrl` 支持的平台和音质。桥接请求支持公网上 HTTP/HTTPS、GET/POST、JSON、表单、multipart、二进制、取消、计时器和已有加密 API。
4. `musicUrl` 返回字符串，保留 HTTP/HTTPS、签名参数和非标准有效端口；不自动升级协议。拒绝本地地址、IP 字面量、非 HTTP(S)、用户信息和私网 DNS 解析结果。
5. 脚本 HTTP 请求逐跳重新校验，拒绝 HTTPS 降级，跨 origin 清理凭据；限制请求和响应体、并发、重定向和等待时间。
6. 原生 AVPlayer 直接加载最终地址，失败时记录已失败链接并重新解析，避免返回旧 URL；保留原来的切歌代际隔离、后台播放、锁屏控制。
7. 优先记住成功的来源。首次失败可在冷却/时限内刷新云索引；同平台解析失败时尝试严格匹配的同曲候选。成功进入播放后才持久化其他平台优选元数据；不持久化临时流地址。

## 安全与已知边界

- ATS 兼容例外允许任意可信公网 HTTP CDN 及 LX HTTP 请求；应用逻辑保留 HTTPS 下载、统计和目录限制。HTTP 不加密，App Review 可能要求说明 ATS 例外。
- JavaScriptCore 不是进程隔离的恶意代码沙箱；无法用公开 API 强制终止恶意同步无限循环。只运行用户信任的脚本，不暴露账户或设备标识。
- DNS 预检不是 DNS pinning。AVPlayer 内部流媒体重定向由系统处理，不能声称对 AVPlayer 每个跳转均实施脚本代理规则。
- 未擅自绕过内容授权、DRM、会员或付费限制。实际第三方接口和音源权限须由用户确认。
- LX 返回值仍遵循标准字符串协议；任意自定义对象、桌面 API、复杂 HTTP 头部专用音频流等未承诺完全兼容。
- Linux 只能执行可移植测试，无法证明 Xcode 27 编译、iOS 16/26/27 真机布局或线上 CDN 播放。

官方 API：
- https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
- https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement
