import SwiftUI
import UniformTypeIdentifiers

struct LXSourceScreen: View {
    @ObservedObject var store:LXSourceStore
    @State private var link=""
    @State private var indexAddress=""
    @State private var note=""
    @State private var working=false
    @State private var refreshing=false
    @State private var importing=false
    @State private var pending:LXSource?
    @State private var confirming=false
    @State private var showIndex=false
    @State private var confirmCloud=false
    var body: some View {
        Form {
            Section {
                Text("LX UserApi v2 · 原生 JavaScriptCore。只导入您信任并有权使用的脚本；脚本可能向其服务发送必要的歌曲信息。").font(.footnote).foregroundStyle(.secondary)
                Button { importing=true } label: { Label("导入本地 .js 文件",systemImage:"doc.badge.plus") }.disabled(working)
                TextField("HTTPS 音源脚本链接",text:$link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { prepare(link) } label: { Label("从链接导入",systemImage:"link") }
                    .disabled(working || link.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                if working { ProgressView("正在读取或初始化音源…") }
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("添加 LX 音源") }
            Section {
                if store.sources.isEmpty { Text("尚未导入 LX 音源").foregroundStyle(.secondary) }
                ForEach(store.sources) { source in
                    VStack(alignment:.leading,spacing:8) {
                        Toggle(isOn:Binding(get:{store.sources.first(where:{$0.id==source.id})?.enabled ?? false},
                                            set:{store.setEnabled(source.id,$0)})) {
                            VStack(alignment:.leading,spacing:3) {
                                Text(source.name).font(.headline)
                                Text([source.metadata.author.nonEmpty,source.metadata.version.nonEmpty.map{"v\($0)"}].compactMap{$0}.joined(separator:" · ").nonEmpty ?? "未声明作者或版本")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(working || source.supported.isEmpty)
                        Text(source.status).font(.caption).foregroundStyle(source.supported.isEmpty ? Color.orange : Color.secondary)
                        ForEach(Platform.online.filter{source.supported[$0.rawValue] != nil}) { platform in
                            HStack(alignment:.firstTextBaseline) {
                                Text(platform.title).font(.caption.weight(.medium))
                                Spacer(minLength:8)
                                Text((source.supported[platform.rawValue] ?? []).joined(separator:" / ")).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            }
                        }
                        if !source.metadata.description.isEmpty {
                            Text(source.metadata.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source.origin).font(.caption2).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        HStack {
                            Button("重新检测") {
                                working=true
                                Task { await store.recheck(source.id);working=false }
                            }.buttonStyle(.borderless).disabled(working)
                            Spacer()
                            if source.origin.hasPrefix("https://") {
                                Button("更新脚本") { prepare(source.origin) }.buttonStyle(.borderless).disabled(working)
                            }
                        }.font(.subheadline)
                    }.padding(.vertical,3)
                }.onDelete { if !working { store.remove(at:$0) } }
                 .onMove { if !working { store.move(from:$0,to:$1) } }
            } header: { Text("已导入 · 从上到下依次尝试") }
              footer: { Text("点击编辑调整优先级或删除。检测成功后可启用；初始化成功不代表音源服务器一定有可播放音频。") }
            Section {
                Toggle("自动使用云端音源",isOn:Binding(get:{store.cloudEnabled},set:{ value in
                    if value { confirmCloud=true }
                    else { store.cloudEnabled=false }
                }))
                TextField("云端 Markdown 索引",text:$indexAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    refreshing=true
                    Task { await store.refreshIndex(indexAddress);refreshing=false }
                } label: {
                    HStack { Label("刷新云端音源索引",systemImage:"arrow.clockwise");Spacer();if refreshing{ProgressView()} }
                }.disabled(refreshing || indexAddress.isEmpty)
                if !store.indexStatus.isEmpty { Text(store.indexStatus).font(.caption).foregroundStyle(.secondary) }
                if let date=store.indexUpdated {
                    Text("上次成功刷新：\(date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(isExpanded:$showIndex) {
                    if store.indexEntries.isEmpty { Text("暂无缓存，点击刷新").font(.caption).foregroundStyle(.secondary) }
                    ForEach(store.indexEntries,id:\.self) { url in
                        Button { prepare(url) } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Text(URL(string:url)?.lastPathComponent ?? url).font(.subheadline.weight(.medium))
                                Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.disabled(working)
                    }
                } label: { Text("可导入链接（\(store.indexEntries.count)）") }
            } header: { Text("云端音源索引") }
              footer: { Text("兼容原安卓 yinyuan.md 的 Markdown/纯文本 HTTPS .js 列表。刷新失败保留缓存。开启自动使用后，在播放时按需下载并执行云端脚本；关闭后只执行您已导入的音源。") }
            Section("运行限制") {
                Text("支持 GET/POST、JSON、表单、文本 multipart、二进制响应、取消请求、MD5、AES-128、RSA、公用字节转换及 setTimeout。脚本与索引下载仅限 HTTPS；音频及 LX 请求支持公网 HTTP/HTTPS，禁止私网地址和 HTTPS 降级。HTTP 不加密，请仅使用受信任音源。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("JavaScriptCore 是进程内执行环境，不是完整安全沙箱。超时可取消等待和网络请求，但无法使用公开 API 强制终止无限循环；此时请重启 App。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error=store.error { Section { Text(error).font(.footnote).foregroundStyle(.orange);Button("关闭提示"){store.error=nil} } }
        }
        .scrollChrome().navigationTitle("LX 音源管理").analyticsPage("network")
        .toolbar { EditButton().disabled(working) }
        .onAppear { if indexAddress.isEmpty { indexAddress=store.indexURL } }
        .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"js") ?? .plainText]) { result in
            do {
                pending=try store.prepareFile(result.get());confirming=true
            } catch { note=error.localizedDescription }
        }
        .alert("信任云端音源索引？",isPresented:$confirmCloud) {
            Button("信任并启用") { store.cloudEnabled=true;Task { await store.refreshCloudIfNeeded() } }
            Button("取消",role:.cancel) {}
        } message: { Text("启用后将按需执行云端第三方 JavaScript。脚本可能发送歌曲信息，且可访问公网 HTTP/HTTPS。请确认索引可信并仅播放有权使用的内容。") }
        .confirmationDialog("确认信任并执行此音源？",isPresented:$confirming,titleVisibility:.visible) {
            Button("信任、导入并检测") {
                guard let draft=pending else { return }
                pending=nil;working=true
                Task {
                    do {
                        let source=try await store.install(draft)
                        note="\(source.name)：\(source.status)"
                        if !source.supported.isEmpty { link="" }
                    } catch { note=error.localizedDescription }
                    working=false
                }
            }
            Button("取消",role:.cancel){pending=nil}
        } message: {
            Text("\(pending?.name ?? "") · \(pending?.metadata.author ?? "") \(pending?.metadata.version ?? "")\n\(pending?.origin ?? "")\n该脚本将执行 JavaScript 并可发起受限 HTTPS 请求。请确认来源可信且有内容使用权限。")
        }
    }
    private func prepare(_ address:String) {
        guard !working else { return }
        working=true;note=""
        Task {
            do { pending=try await store.prepareURL(address);confirming=true }
            catch { note=error.localizedDescription }
            working=false
        }
    }
}
