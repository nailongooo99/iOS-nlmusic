# Android 3.0 → iOS 1.0 迁移矩阵

以用户上传的 Android 3.0 工程为主；读取过 `MusicModels.kt`、`MusicApi.kt`、
`MusicCatalogAdapters.kt`、`MusicDetailApi.kt`、`CurrentMusicServices.kt`、`BackupCodec.kt`、
`UserApiEngine.kt`、`RemoteSources.kt`、`lx-user-api-bridge.js`、`SettingsDetail.kt` 与图标矢量；
参考 CurrentMusicX / LX Mobile 的原始项目与 Android 工程中的整合逻辑。不是将原 Android
所有类逐行翻译。本表的“已写入”表示代码和界面已有实现，并非真机或真实服务验收成功。

| Android 功能 | iOS 实现 | 边界 / 状态 |
|---|---|---|
| Glasmio iOS 玻璃 / COUI 双样式 | SwiftUI 原生 Liquid Glass / Material，系统主题、导航和 SF Symbols | 改用 Apple 原生样式，不保留 COUI 或玻璃折射五档 |
| 开屏动画与启动恢复 | iOS LaunchScreen 与系统界面进入 | 未复刻品牌飞入、双层 Android GPU 恢复 |
| 首页每日推荐 / 黑胶 / 榜单 | 公开新歌、封面卡片、五平台榜单及回退索引 | 已写入，未实测服务 |
| 五平台歌曲搜索 | 网易云、QQ、酷狗、酷我、咪咕目录请求 | 已写入，部分接口为公开/兼容路径，并非全部签名回退；服务可能拒绝或更改 |
| 五平台歌单搜索 / 热门歌单 | 目录、分页、空状态、排序入口 | 已写入；酷狗、咪咕排序与 Android 不完全等价 |
| 歌单详情与分享链接导入 | 公开详情、长 ID、验证预览、收藏和分页 | 完整 URL/数字 ID；未实现酷狗/QQ等短链重定向及全部详情备用协议 |
| 本地歌单 / 收藏 / 历史 | 原子 JSON 保存、新建、添加/移除、历史 | 已写入 |
| 本地文件播放 | Files 音频导入、应用私有目录、授权 HTTPS 直链 | 已写入；不自动转移 Android 文件授权 |
| LX UserApi v2 自定义脚本 / 云索引 | JavaScriptCore、.js 文件与 HTTPS 导入、原云端 Markdown 索引、初始化/状态/音质、启停排序 | 已实现协议主链路，需真实 Apple 框架及脚本联调；云脚本须用户确认启用，之后按需自动尝试，不批量执行全部索引 |
| CurrentMusic 网易云直连 | 不提供内置第三方音频解析；允许授权服务 | **未移植** |
| CurrentMusic 线路自动择优 | 四条原有线路的 HTTP 探测、手动复测、歌词回退 | 已写入；线路未联调 |
| 播放器 / 缓冲 / URL失效恢复 | AVPlayer、就绪/失败观察、限时尝试、最多两次地址重解 | 已写入；失败地址排除、质量回退均需实测 |
| 顺序 / 随机 / 单曲 / 列表循环 | 自定义队列策略、下一首、上一首、插队、删除 | 已写入，核心策略有测试 |
| 记忆进度、音量、后台/锁屏/耳机 | AVAudioSession、MPNowPlayingInfoCenter、MPRemoteCommandCenter、MPVolumeView | 已写入，真机必测 |
| 跨平台歌曲自动严格匹配、自动优选持久化 | 可读取备份中的优选源引用并尝试解析 | 未实现自动匹配或手动跨平台绑定界面 |
| 智能过渡 / 等功率淡入淡出 / 下一首预加载 | 普通切歌 | **未实现双播放器过渡、预加载及移动网络开关** |
| 全屏播放器 / 迷你播放条 | 原生播放器、滚动联动紧凑模式、左四主菜单与右侧独立搜索、Liquid Glass/Material | 已写入；未实现同一封面飞行动画，需真机验证缩放及手势 |
| 普通歌词 / 逐字歌词 / 翻译 | LRC、增强 LRC、网易云 YRC、翻译、滚动、高亮、点击跳转、导入 LRC | 已写入基础解析与逐词点亮，不是全平台逐字格式 |
| 五平台歌词请求 | 网易云 YRC/LRC、QQ LRC、酷狗 LRC、酷我兼容逐行、咪咕 LRC/TRC | 代码已接入，未联调；未实现 QQ 加密 QRC、酷狗 KRC、酷我加密 LRCX、咪咕 MRC、罗马音和高潮区间 |
| 评论 | 五平台公开评论适配与分页 | 已写入，未联调；不是 Android 全部热评/最新评论/图片评论及游标行为 |
| 桌面歌词悬浮窗 / 蓝牙歌词 | 锁屏显示歌曲元数据，应用内歌词 | iOS 无 Android `SYSTEM_ALERT_WINDOW` 等价公共 API；无全局悬浮歌词或通用蓝牙歌词推送 |
| 搜索历史 / 热词 / 联想 | 搜索历史、清空确认、类型和平台选择 | 未实现热搜与联想 |
| 统计 / 唱片墙 | 播放时间记录、排行、海报/壁纸 PNG 及系统分享 | 已写入，未实机验证导出 |
| 资源缓存 / 存储管理 | URLCache、文件容量读取、清理缓存 | 未实现 Android 20GiB 分类音频缓存、离线在线音频下载及逐类别清理 |
| 备份 v1–v4 | JSON 校验、恢复确认、导出便携 v4 | 核心格式离线测试，未真机往返；本地音频文件需另外迁移 |
| 公告 / 关于 / 法律文档 | 原有 Markdown URL + SwiftUI 文本渲染 | 已写入简化 Markdown，未实现全部表格/图片/HTML 扩展 |
| Android APK 强制更新 | iOS 分发走签名与系统安装 | 不复用安卓更新协议；未配置独立 iOS 版本服务 |
| 访问分析 PHP/MySQL | 同字段 JSON POST、前台访问/30 秒心跳/离开、关闭开关 | 已实现客户端；iOS 硬件与 sdk 字段有平台差异，生产 PHP/MySQL 尚未联调 |
| Android 触摸时网络门控 | iOS 任务取消、请求大小和时限限制 | 未移植全局触摸网络冻结 |
| 横屏/平板、辅助功能 | SwiftUI 自适应，系统字体、辅助标签、减少动效 | 源码已接线，iPhone/iPad/动态字体/不同系统需要验收 |

## 主要自主决策

- iOS 独立 Bundle ID `com.nailong.music.ios`；避免 `com.apple.android.music` 冒用
  Apple 反向域名或与 Android 包名耦合，最终请用自己的开发者账户可注册的 App ID。
- 首选 320k、无默认外部音频解析器、主题跟随系统。
- 只使用 HTTPS 目录及音源请求；LX 支持用户确认后执行，不自动运行云索引或脚本更新；不复制 Android 明文网络配置。
- 保留用户原图标，删除所有 Android 运行时依赖。iOS 26/27 使用系统 TabView、底栏附件和收缩 API，
  旧系统回落系统 Material，而非移植 Android shader。
- 默认不收集访问分析；用户主动配置的服务和平台可收到必要的请求数据。
- 无签名包标明不可直接安装；签名仅在用户手动触发工作流时读取 Secrets。

后续完成完整等价移植时，优先补齐真实 LX 音源接口测试、QQ/KG/KW/MG
逐字歌词格式、跨平台源匹配、预加载/歌曲过渡、持久资源缓存、搜索联想及完整 API 备用链。
