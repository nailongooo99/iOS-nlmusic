import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: Library
    @State private var clear = false
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题",selection:$settings.theme) {
                    Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
                Text("iOS 26 及以后使用系统 Liquid Glass；较早系统使用原生系统材质。").font(.caption).foregroundStyle(.secondary)
            }
            Section("音乐与播放") {
                NavigationLink { SourceScreen() } label: { Label("音源与网络",systemImage:"network") }
                Picker("首选音质",selection:$settings.quality) {
                    Text("标准 128k").tag("128k"); Text("高品质 320k").tag("320k"); Text("无损 FLAC").tag("flac"); Text("高解析无损").tag("flac24bit")
                }
                Toggle("耳机断开时暂停",isOn:$settings.pauseRoute)
                Toggle("与其他 App 混音",isOn:$settings.mix)
                Toggle("记住播放进度",isOn:$settings.rememberProgress)
                Toggle("显示翻译歌词",isOn:$settings.translation)
            }
            Section("数据") {
                NavigationLink { BackupScreen() } label: { Label("备份管理",systemImage:"externaldrive") }
                Toggle("保存搜索历史",isOn:$settings.saveSearch)
                Button("清空搜索历史",role:.destructive) { clear = true }
                NavigationLink { StorageScreen() } label: { Label("存储管理",systemImage:"internaldrive") }
            }
            Section("公告与关于") {
                NavigationLink { RemoteDocument(title:"公告",url:"https://www.nailong.link/nlmusic/gonggao.md") } label: { Label("公告",systemImage:"megaphone") }
                NavigationLink { AboutScreen() } label: { Label("关于奶龙音乐",systemImage:"info.circle") }
            }
        }.navigationTitle("设置")
        .confirmationDialog("确定清空搜索历史？",isPresented:$clear,titleVisibility:.visible) {
            Button("清空",role:.destructive) { library.change { $0.searches = [] } }
            Button("取消",role:.cancel) {}
        }
    }
}
struct SourceScreen: View {
    @EnvironmentObject var settings: Settings
    @State private var name = ""
    @State private var endpoint = ""
    @State private var note = ""
    @State private var measuring = false
    var body: some View {
        Form {
            Section {
                Text("仅配置您拥有访问及播放权限的音源。未内置免费音源；目录搜索不代表获得音频播放许可。").font(.footnote).foregroundStyle(.secondary)
                ForEach(settings.sources) { source in
                    VStack(alignment:.leading,spacing:5) { Text(source.name).font(.headline); Text(source.endpoint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.onDelete(perform:settings.remove).onMove(perform:settings.move)
                TextField("音源名称",text:$name)
                TextField("HTTPS 服务地址",text:$endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("添加音源") {
                    do {
                        try settings.addSource(name:name,endpoint:endpoint.trimmingCharacters(in:.whitespacesAndNewlines))
                        name = ""; endpoint = ""; note = "已添加，可在播放时自动尝试"
                    } catch { note = error.localizedDescription }
                }.disabled(name.isEmpty || endpoint.isEmpty)
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("授权音源服务 · 按列表顺序优选") }
            Section("CurrentMusic 歌词服务") {
                Toggle("自动测速择优",isOn:$settings.autoRoute)
                Text(settings.service).font(.footnote).textSelection(.enabled)
                Button { Task { measuring = true; await settings.measure(); measuring = false } } label: {
                    HStack { Text("重新测速"); Spacer(); if measuring { ProgressView() } }
                }.disabled(measuring)
                Text(settings.routeStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("音源接口说明") {
                Text("POST JSON：platform、id、title、artist、quality、metadata。返回 JSON：url（HTTPS 音频地址），可选 lyrics（LRC/YRC 文本）。自动按首选音质向下回退。").font(.footnote)
                Text("安卓 LX UserApi JavaScript 不能直接作为 HTTPS 地址导入。本版本不自动执行云端 JS。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("音源与网络").toolbar { EditButton() }
    }
}
struct BackupScreen: View {
    @EnvironmentObject var library: Library
    @State private var exporting = false
    @State private var importing = false
    @State private var confirm = false
    @State private var pending: LibraryBackup?
    @State private var document: BackupDocument?
    @State private var note = ""
    var body: some View {
        Form {
            Section("跨端音乐库") {
                Button { do { document = BackupDocument(data:try library.exportBackup()); exporting = true } catch { note = error.localizedDescription } } label: { Label("导出备份",systemImage:"square.and.arrow.up") }
                Button { importing = true } label: { Label("导入备份",systemImage:"square.and.arrow.down") }
                Text("支持奶龙 Android v1–v4 JSON 备份。包含收藏、历史、歌单、搜索记录、统计和优选音源引用；不包含本地音频及其记录、账号、音源服务配置和临时播放链接；本地音频需要另行保留。恢复会覆盖现有音乐库。").font(.footnote).foregroundStyle(.secondary)
                if !note.isEmpty { Text(note).foregroundStyle(.secondary) }
            }
        }.navigationTitle("备份管理")
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"NailongMusic-library-v4") { result in
            switch result { case .success: note = "备份已导出"; case .failure(let error): note = error.localizedDescription }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            do { pending = try library.readBackup(result.get()); confirm = true }
            catch { note = error.localizedDescription }
        }
        .confirmationDialog("覆盖当前音乐库？",isPresented:$confirm,titleVisibility:.visible) {
            Button("确认恢复",role:.destructive) { if let pending { library.restore(pending); note = library.error ?? "备份恢复完成" }; pending = nil }
            Button("取消",role:.cancel) { pending = nil }
        } message: { Text("建议先导出当前音乐库。") }
    }
}
struct StorageScreen: View {
    @EnvironmentObject var library: Library
    @State private var size: Int64 = 0
    @State private var note = ""
    var body: some View {
        Form {
            Section("本地存储") {
                LabeledContent("导入音频",value:ByteCountFormatter.string(fromByteCount:size,countStyle:.file))
                Button("刷新统计") { scan() }
                Text("导入音频保存在应用私有目录，不属于临时缓存。删除歌单不会删除文件。请保留原始文件以便恢复。").font(.caption).foregroundStyle(.secondary)
            }
            Section("网络缓存") {
                Button("清理 URL 缓存",role:.destructive) { URLCache.shared.removeAllCachedResponses(); note = "URL 缓存已清理" }
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("存储管理").onAppear(perform:scan)
    }
    private func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at:library.localDirectory,includingPropertiesForKeys:[.fileSizeKey])) ?? []
        size = files.reduce(0) { total,url in total + Int64((try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
    }
}
struct RemoteDocument: View {
    let title: String
    let url: String
    @State private var content = ""
    @State private var note = ""
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                if loading { ProgressView().frame(maxWidth:.infinity) }
                if !content.isEmpty {
                    // Parse each Markdown line separately, without HTML/script execution.
                    ForEach(Array(content.components(separatedBy:.newlines).enumerated()),id:\.offset) { _,line in
                        if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.title.bold()) }
                        else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.title2.bold()) }
                        else if let rich = try? AttributedString(markdown:line) { Text(rich).textSelection(.enabled) }
                        else { Text(line).textSelection(.enabled) }
                    }
                }
                if !note.isEmpty { Text(note).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
            }.padding().frame(maxWidth:.infinity,alignment:.leading)
        }.navigationTitle(title).task { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { content = try await WebClient.text(url); note = "" }
        catch { if !Task.isCancelled { note = "文档暂不可用：\(error.localizedDescription)" } }
    }
}
struct AboutScreen: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing:14) {
                    Image("BrandIcon").resizable().scaledToFit().frame(width:70,height:70).clipShape(RoundedRectangle(cornerRadius:16))
                    VStack(alignment:.leading,spacing:5) {
                        Text("奶龙音乐").font(.title2.bold())
                        Text("iOS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("应用标识",value:Bundle.main.bundleIdentifier ?? "com.nailong.music.ios")
                LabeledContent("技术架构",value:"SwiftUI · AVFoundation")
            }
            Section("法律与来源") {
                NavigationLink("免责声明") { RemoteDocument(title:"免责声明",url:"https://www.nailong.link/nlmusic/mzsm.md") }
                NavigationLink("隐私政策") { RemoteDocument(title:"隐私政策",url:"https://www.nailong.link/nlmusic/yszc.md") }
                NavigationLink("开源协议") { RemoteDocument(title:"开源协议",url:"https://www.nailong.link/nlmusic/kyxy.md") }
                NavigationLink("本地第三方声明") {
                    ScrollView {
                        Text((try? String(contentsOf:Bundle.main.url(forResource:"THIRD_PARTY_NOTICES",withExtension:"txt") ?? URL(fileURLWithPath:"/nonexistent"),encoding:.utf8)) ?? "请查看项目随附 LICENSES 目录。").textSelection(.enabled).padding()
                    }.navigationTitle("第三方声明")
                }
                Link("奶龙音乐网站",destination:URL(string:"https://www.nailong.link/")!)
            }
            Section {
                Text("独立音乐客户端。与 Apple、网易云音乐、QQ音乐及其他音乐平台无官方合作关系。请仅播放和导入有权使用的内容。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("关于")
    }
}
