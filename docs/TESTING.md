# 验证记录与验收

## 当前执行环境

Linux，Swift 工具链可用，无 Xcode、无 iOS SDK、无 Simulator、无真实 iPhone、无 Apple
签名资产。没有 GitHub 仓库写入权限，也没有执行 GitHub Actions。交付是开发源代码和
构建配置，不是验证可安装的 IPA。

已经执行：

- `bash scripts/test-core.sh`：编译并执行 Foundation 核心测试，30 项核心检查通过（新增 6 项歌单写入回归检查）。
  覆盖普通/增强 LRC、YRC 时间轴、合并普通歌词、循环队列、跨平台键、备份隐私过滤、
  v1 格式解码、无效版本拒绝与时间格式。
- `swiftc -frontend -parse`：全部 iOS Swift 文件语法解析通过。不能替代 SwiftUI、
  AVFoundation、MediaPlayer 的真实 iOS SDK 类型检查及链接。
- `plutil -lint`：Info.plist、隐私清单和 OpenStep Xcode project.pbxproj 语法通过。
- `bash -n scripts/*.sh`：各脚本语法通过。
- ZIP 归档完整性检查；不包含用户密钥、配置文件或 Android 源码副本。

CI 首次执行才会验证真实 Xcode SDK 的类型检查、链接、资源编译和设备 IPA 归档。
工作流报错时保留第一个编译错误的完整日志（尤其是 Swift/SDK availability），不要
将未编译成功的归档当成发行版。

## 真机验收矩阵（均待执行）

1. iOS 16.x 真实设备（当前 Xcode 27 不直接支持 iOS 16 调试/模拟器；可用符合设备的签名安装测试），
   iOS 17/18、iOS 26、iOS 27，至少一台小屏 iPhone 与一台 iPad。
2. 浅色、暗色、系统跟随；横竖屏、安全区、较大动态字体、VoiceOver、减少动态效果。
3. 首页：正常网络、断网、空响应、401/403/404、五平台切换；歌曲/歌单搜索及分页；
   QQ 长整数 ID 公开歌单导入、无效域名拒绝、私有歌单错误。
4. Files 导入自有 MP3/AAC、合法 HTTPS 音频直链，首次播放/暂停/继续、跳转、
   四种循环、下一首/上一首、队列插入及删除；本地文件缺失时错误提示。
5. 使用自己有权使用的 HTTPS 解析服务，五平台 ID / 四档质量、有效/过期 URL、
   错误响应、超时、质量回退与两次有限重解。测试 FLAC/高解析实际 AVPlayer 支持。
6. 锁屏、控制中心、AirPods/蓝牙耳机、耳机断开、电话/音频中断、后台长时间播放与恢复。
7. LRC、YRC、翻译、长歌词、尾行补全、点击跳转、导入本地歌词，五平台公开评论及失败提示。
8. 收藏、历史、自建歌单、Android v1–v4 备份导入/导出往返、
   损坏文件/超限文件、确认覆盖、Android 本地文件不可移植提示。
9. 真实播放统计、无记录/缺封面/多曲目海报及壁纸 PNG、系统分享保存、存储缓存清理。
10. 两种签名：证书匹配、描述文件匹配、UDID 注册、签名过期错误；
    安装后核对 App 显示名称、版本 1.0、MinimumOSVersion 16.0。
11. 每项按“通过 / 失败 / 不支持 / 未测”记录，记录 iOS 版本、设备与可复现步骤，
    分享日志前隐藏 token、Cookie、签名 URL、证书及个人路径。

完整功能差异请见 MIGRATION.md。上述待验收事项并非已通过项目。

## 首次 Actions 构建修复

原版 `Library.add` 对同一个可选数组的重叠访问已经用 Swift 编译器复现并修正。实际使用的歌单修改方法已移入 Core，加入回归检查。工作流保留模拟器和设备编译门槛，增加失败诊断摘要和无签名编译日志下载。此次仍未在本地运行 Xcode，下一次 Actions 是实际 iOS SDK 验证。

## LX 与浮动底栏更新验证

- 51 项核心逻辑检查已通过，包含 LX 标准初始化、音质回退、元数据、索引和 HTTPS 校验。
- Node `tests/LXBridgeTests.js` 使用离线假宿主验证事件、回调、二进制、取消、计时器与字节工具；不代表真实 Apple 加密 API 已验证。
- 新增 `scripts/test-lx-native.sh` 在 macOS Actions 使用真实 JavaScriptCore、Security、CommonCrypto 做离线 smoke test；当前 Linux 未运行此测试。
- 新增 Swift 文件语法解析、LX runtime/store 的 Linux 平台接口替身类型检查、Xcode 工程语法检查通过。
- 真机待测：本地文件与 HTTPS 脚本导入、音源初始化/解析/切歌/后台、全部平台音质、云索引、iOS 16–27 底栏显隐/缩放、iPad 和键盘避让、辅助功能。初始化成功不等于实际音频可播放。
