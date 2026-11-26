# 使用情况统计：与 Android ActivityAnalytics.kt 协议对照

服务地址（不含引号）：

`https://www.nailong.link/nlmusic/nailong-analytics/public/api.php?action=ingest`

源文件：`Core/AnalyticsProtocol.swift`（纯 Swift wire model）、`Services/ActivityAnalytics.swift`（生命周期、队列、HTTPS 传输）以及 `NailongMusicApp.swift`（页面和前后台绑定）。
参照上传 Android 项目 `app/src/main/java/com/apple/android/music/ActivityAnalytics.kt`、`MainActivity.kt`、`MusicModels.kt`。

## 上报字段（所有 13 个字段及 JSON 类型）

| 字段 | 类型 | iOS 处理 |
|---|---|---|
| installation | string | 随机 UUID，持久化在本地 UserDefaults；重启/升级保留，正常卸载/清除应用数据及关闭统计后重建。系统备份恢复行为可能不同。 |
| session | string | 前台会话随机 UUID；进入后台后重建 |
| visit | string | 每次页面访问随机 UUID |
| page | string | Android 同名页面枚举，见下方 |
| elapsed | integer | 连续单调时钟计时的累计秒数，0…86400 |
| closed | boolean | 打开/心跳 false，离开 true |
| model | string | iPhone/iPad 非唯一硬件型号代码（模拟器回退为设备类型），最多 80 字符 |
| brand | string | Apple，最多 60 字符 |
| soc | string | 空字符串；iOS 无与 Android Build.SOC_MODEL 对等且稳定的公开接口，不伪造 |
| soc_vendor | string | Apple，最多 60 字符 |
| os | string | iOS 系统版本，最多 30 字符 |
| sdk | integer | iOS 系统主版本（如 27）；不是 Android API level |
| app | string | CFBundleShortVersionString，固定发行版本 1.0 |

上传的 Android `ActivityAnalytics.kt` 中 `ENDPOINT` 为空、`app` 硬编码为 `"2.0"`；这里按需求设置实际 HTTPS 地址和 iOS 的 `1.0`。
iOS 和 Android 的系统字段无法数值完全等同。服务端 PHP 源码没有提供，必须验证它不把 `sdk` 强制解释为 Android API level、不拒绝空 `soc`，并能正确区分平台（例如通过 `brand`）。

## 行为对照

- 默认开启，可在「设置 → 隐私与统计」关闭。说明了采集范围与目标；关闭取消心跳、清空队列、取消正在进行的 best-effort 请求、清除安装标识并重置会话。已发到服务端的请求无法撤回。
- 前台打开页面立即上报，30 秒一次累计心跳，切换页面离开时 `closed=true`。同一页面心跳复用 visit、session、installation。进入后台结束该访问并重置 session；仅尝试短暂完成已入队的前台事件，不后台产生新的事件。
- 固定容量 32 的内存队列，串行 best-effort HTTPS POST，5 秒请求/资源超时，不跟随重定向，无持久离线队列，不循环重试。`Content-Type` 和 `Accept` 都为 `application/json`。
- 页面代号：`home`, `playlists`, `mine`, `settings`, `search`, `player`, `collection`, `stats`, `backup`, `storage`, `about`, `privacy`, `network`, `license`, `disclaimer`, `detail`。未分类页面使用 detail，不发送标题或搜索词。
- 不采集 IDFA、IDFV、设备序列号、账号、MAC、位置、查询词、歌名、播放地址、Cookie、账号凭据。安装 UUID 仅用于分析，不用于广告追踪。
- iOS 进程被强制杀死、后台过早挂起、网络故障时不保证发送最终 closed（Android 同样为 best effort）。
- `PrivacyInfo.xcprivacy` 声明安装级 ID、产品互动、设备诊断数据用于 Analytics，NSPrivacyTracking=false。公开分发前应同步实际网站隐私政策和 App Store Connect 隐私标签。

## 联调清单（不要用生产统计制造测试记录）

使用自己控制的测试服务或测试环境。若需重定向端点，请在测试分支修改 `AnalyticsProtocol.endpoint`，不要修改正式版本。
1. 捕获首次访问与 30 秒心跳；三种 UUID 不变，elapsed 单调增加且为整数。
2. 首页→搜索→播放器→设置：上一访问 closed，新访问 UUID 不同，session 相同。
3. 退后台再进入：关闭旧 visit，session 变化，installation 保持。
4. 禁用统计：不再上报，随机 installation 被清除；重新开启生成新 UUID。
5. 验证 3xx 不跳转、离线无磁盘重试、页面值不含任何用户输入；验证 PHP/MySQL 对 13 个字段、UUID、空 soc、Apple、iOS 主版本及 app=1.0 的处理。

未向生产 ingest 地址发出测试 POST；当前无法核实 PHP 响应、数据库写入及统计看板。
