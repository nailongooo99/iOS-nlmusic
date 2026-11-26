import Foundation
import SwiftUI

@MainActor final class LXSourceStore: ObservableObject {
    static let defaultIndex = "https://www.nailong.link/nlmusic/yinyuan.md"
    @Published private(set) var sources:[LXSource]=[]
    @Published private(set) var indexEntries:[String]=[]
    @Published private(set) var indexURL="https://www.nailong.link/nlmusic/yinyuan.md"
    @Published private(set) var indexUpdated:Date?
    @Published var indexStatus=""
    @Published var error:String?
    private let directory:URL
    @AppStorage("lxCloudEnabled") var cloudEnabled:Bool=false { willSet { objectWillChange.send() } }
    private var cooldown:[String:Date]=[:]
    private var preferred:[String:String]=[:]
    private var cloudScripts:[String:(source:LXSource,loaded:Date)]=[:]
    private var refreshingIndex=false
    private var cloudAttemptedAt=Date.distantPast
    private func sourceKey(_ source:LXSource) -> String {
        source.origin.hasPrefix("https://") ? source.origin : source.id.uuidString
    }
    private var readFailed=false
    private struct IndexCache:Codable {
        var url:String
        var entries:[String]
        var updated:Date?
    }
    init() {
        directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("NailongMusic/LX",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file=directory.appendingPathComponent("sources.json")
            if FileManager.default.fileExists(atPath:file.path) {
                let attributes=try file.resourceValues(forKeys:[.fileSizeKey])
                guard (attributes.fileSize ?? 0)<=32*1024*1024 else { throw MusicError.message("LX 音源文件超限") }
                sources=try JSONDecoder().decode([LXSource].self,from:Data(contentsOf:file))
            }
        } catch { readFailed=true;self.error="LX 音源读取失败，原文件已保留：\(error.localizedDescription)" }
        let file=directory.appendingPathComponent("index.json")
        if let data=try? Data(contentsOf:file),data.count<=512*1024,
           let cache=try? JSONDecoder().decode(IndexCache.self,from:data),
           (try? LXProtocol.httpsURL(cache.url)) != nil {
            indexURL=cache.url;indexEntries=LXProtocol.indexURLs(cache.entries.joined(separator:"\n"));indexUpdated=cache.updated
        }
    }
    private func persist(_ list:[LXSource]) throws {
        guard !readFailed else { throw MusicError.message("原音源库读取失败，已禁止覆盖；请先备份应用数据") }
        guard list.count<=20 else { throw MusicError.message("最多导入 20 个 LX 音源") }
        let data=try JSONEncoder().encode(list)
        guard data.count<=32*1024*1024 else { throw MusicError.message("音源库体积超限") }
        try data.write(to:directory.appendingPathComponent("sources.json"),options:.atomic)
        sources=list
    }
    private func save(_ list:[LXSource]) {
        do { try persist(list) } catch { self.error=error.localizedDescription }
    }
    func remove(_ id:UUID) { if let source=sources.first(where:{$0.id==id}) { cooldown.removeValue(forKey:sourceKey(source)) };save(sources.filter{$0.id != id}) }
    func remove(at offsets:IndexSet) {
        var copy=sources;copy.remove(atOffsets:offsets);save(copy)
    }
    func move(from offsets:IndexSet,to index:Int) {
        var copy=sources;copy.move(fromOffsets:offsets,toOffset:index);save(copy)
    }
    func setEnabled(_ id:UUID,_ enabled:Bool) {
        guard let i=sources.firstIndex(where:{$0.id==id}) else { return }
        var copy=sources
        guard !enabled || !copy[i].supported.isEmpty else { error="请先通过音源初始化检查";return }
        copy[i].enabled=enabled;save(copy)
        if enabled { cooldown.removeValue(forKey:sourceKey(copy[i])) }
    }
    private func draft(_ data:Data,origin:String,fallback:String) throws -> LXSource {
        guard !data.isEmpty,data.count<=LXProtocol.maxScriptBytes,
              var script=String(data:data,encoding:.utf8) else { throw MusicError.message("音源必须为不超过 1 MiB 的 UTF-8 JavaScript 文件") }
        if script.hasPrefix("\u{feff}") { script.removeFirst() }
        let preview=script.trimmingCharacters(in:.whitespacesAndNewlines).prefix(512).lowercased()
        guard !preview.isEmpty,!preview.hasPrefix("<!doctype"),!preview.hasPrefix("<html"),
              !script.contains("\0") else { throw MusicError.message("地址未返回有效 JavaScript 文件") }
        return LXSource(metadata:LXMetadata.parse(script,fallback:fallback),origin:origin,script:script)
    }
    func prepareFile(_ url:URL) throws -> LXSource {
        let access=url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased()=="js" else { throw MusicError.message("请选择 .js 音源文件") }
        let file=try FileHandle(forReadingFrom:url)
        defer { try? file.close() }
        var data=Data()
        while data.count<=LXProtocol.maxScriptBytes {
            let count=min(65536,LXProtocol.maxScriptBytes+1-data.count)
            guard let part=try file.read(upToCount:count),!part.isEmpty else { break }
            data.append(part)
        }
        return try draft(data,origin:"文件："+url.lastPathComponent,fallback:url.deletingPathExtension().lastPathComponent)
    }
    func prepareURL(_ raw:String) async throws -> LXSource {
        let url=try LXProtocol.httpsURL(raw)
        let data=try await LXNetwork.load(url.absoluteString,maxBytes:LXProtocol.maxScriptBytes)
        return try draft(data,origin:url.absoluteString,fallback:url.deletingPathExtension().lastPathComponent.nonEmpty ?? url.host ?? "LX 音源")
    }
    // Called only after explicit user confirmation. Even failed sources are
    // saved disabled so users can see the diagnostic or replace the script.
    func install(_ draft:LXSource) async throws -> LXSource {
        var candidate=draft
        let previous=sources.first(where:{$0.origin==draft.origin || $0.script==draft.script})
        if let previous { candidate.id=previous.id }
        guard previous != nil || sources.count<20 else { throw MusicError.message("最多导入 20 个音源") }
        candidate=try await checked(candidate,enableIfValid:previous?.enabled ?? true)
        if let previous,!previous.supported.isEmpty,candidate.supported.isEmpty {
            throw MusicError.message("更新未通过初始化，原音源已保留。"+candidate.status)
        }
        var list=sources
        if let i=list.firstIndex(where:{$0.id==candidate.id}) { list[i]=candidate }
        else { list.append(candidate) }
        try persist(list)
        cooldown.removeValue(forKey:sourceKey(candidate))
        return candidate
    }
    func recheck(_ id:UUID) async {
        guard let source=sources.first(where:{$0.id==id}) else { return }
        do {
            let verified=try await self.checked(source,enableIfValid:source.enabled)
            var list=sources
            guard let i=list.firstIndex(where:{$0.id==id && $0.script==source.script}) else { return }
            list[i]=verified;try persist(list);cooldown.removeValue(forKey:sourceKey(verified))
        } catch is CancellationError {} catch { self.error=error.localizedDescription }
    }
    private func checked(_ source:LXSource,enableIfValid:Bool) async throws -> LXSource {
        var candidate=source
        let runtime=LXRuntime()
        defer { runtime.close() }
        do {
            candidate.supported=try await runtime.initialize(source)
            candidate.enabled=enableIfValid
            candidate.status="初始化成功"+(runtime.updateNote.isEmpty ? "" : " · 有更新提示")
        } catch is CancellationError { throw CancellationError() }
        catch {
            candidate.enabled=false;candidate.supported=[:]
            candidate.status="初始化失败："+String(error.localizedDescription.prefix(200))
        }
        candidate.checkedAt=Date()
        return candidate
    }
    func refreshIndex(_ address:String) async {
        guard !refreshingIndex else { return }
        refreshingIndex=true
        defer { refreshingIndex=false }
        cloudAttemptedAt=Date()
        indexStatus="正在刷新…"
        do {
            let url=try LXProtocol.httpsURL(address)
            let bytes=try await LXNetwork.load(url.absoluteString,maxBytes:128*1024)
            guard let text=String(data:bytes,encoding:.utf8) else { throw MusicError.message("索引不是 UTF-8 文本") }
            let entries=LXProtocol.indexURLs(text)
            guard !entries.isEmpty else { throw MusicError.message("索引未包含有效 HTTPS .js 链接") }
            let updated=Date()
            let data=try JSONEncoder().encode(IndexCache(url:url.absoluteString,entries:entries,updated:updated))
            try data.write(to:directory.appendingPathComponent("index.json"),options:.atomic)
            indexURL=url.absoluteString;indexEntries=entries;indexUpdated=updated
            indexStatus="已发现 \(entries.count) 条音源链接"
        } catch is CancellationError { indexStatus="已取消刷新" }
        catch { indexStatus="刷新失败，保留上次索引："+String(error.localizedDescription.prefix(160)) }
    }
    // Cloud index is fetched independently of installation. The user explicitly
    // enables cloud scripts; a candidate is downloaded only when playback needs it.
    func refreshCloudIfNeeded() async {
        guard cloudEnabled, !refreshingIndex,
              Date().timeIntervalSince(cloudAttemptedAt)>60,
              indexEntries.isEmpty || Date().timeIntervalSince(indexUpdated ?? .distantPast)>1800 else { return }
        await refreshIndex(indexURL)
    }
    private func cloudSource(_ address:String) async throws -> LXSource {
        if let cached=cloudScripts[address],Date().timeIntervalSince(cached.loaded)<600 { return cached.source }
        let source=try await prepareURL(address)
        if cloudScripts.count>=12 { cloudScripts.removeAll(keepingCapacity:true) }
        cloudScripts[address]=(source,Date())
        return source
    }
    func resolve(_ track:Track,quality:String,excluding:Set<String>,deadline:Date,allowRefresh:Bool=true) async throws -> URL {
        // If there is no installed source, a cloud fetch may be needed before the
        // first resolution. Otherwise prefer the user's installed sources first.
        if cloudEnabled && sources.allSatisfy({!$0.enabled}) { await refreshCloudIfNeeded() }
        cooldown=cooldown.filter{$0.value>Date()}
        let platform=track.platform.rawValue
        let enabled=sources.filter{$0.enabled}
        let installedKeys=Set(sources.map{sourceKey($0)})
        var candidates:[(key:String,source:LXSource?)]=enabled.map{(sourceKey($0),$0)}
        if cloudEnabled {
            candidates += indexEntries.filter{!installedKeys.contains($0)}.map{($0,nil)}
        }
        var seen=Set<String>()
        candidates=candidates.filter{seen.insert($0.key).inserted}
        // Stable preference per platform, then installed priority, then cloud order.
        if let favored=preferred[platform],let i=candidates.firstIndex(where:{$0.key==favored}),cooldown[favored]==nil {
            let item=candidates.remove(at:i);candidates.insert(item,at:0)
        }
        let ordered=candidates.filter{cooldown[$0.key]==nil}+candidates.filter{cooldown[$0.key] != nil}
        var last=ordered.isEmpty ? "暂无已启用音源，请导入 LX 脚本或启用云端音源" : "没有音源支持此平台及音质"
        for candidate in ordered.prefix(12) {
            try Task.checkCancellation()
            if deadline.timeIntervalSinceNow<=0 { break }
            if candidate.source==nil && !cloudEnabled { continue }
            let runtime=LXRuntime()
            defer { runtime.close() }
            var name=candidate.source?.name ?? "云端音源"
            do {
                let source:LXSource
                if let installed=candidate.source { source=installed }
                else { source=try await cloudSource(candidate.key) }
                name=source.name
                try Task.checkCancellation()
                if candidate.source==nil && !cloudEnabled { continue }
                guard deadline.timeIntervalSinceNow>0 else { break }
                let supported=try await runtime.initialize(source,timeout:min(12,max(0.1,deadline.timeIntervalSinceNow)))
                let offered=LXProtocol.order(quality,supported:supported[platform] ?? [])
                guard !offered.isEmpty else { last="\(name) 不支持 \(track.platform.title) 的所选音质";continue }
                for q in offered {
                    try Task.checkCancellation()
                    if deadline.timeIntervalSinceNow<=0 { break }
                    do {
                        let address=try await runtime.resolve(track,quality:q,timeout:min(18,max(0.1,deadline.timeIntervalSinceNow)))
                        let url=try await LXNetwork.checked(address,allowHTTP:true)
                        guard !excluding.contains(address),!excluding.contains(url.absoluteString) else {
                            throw MusicError.message("音源返回已失败的旧播放链接")
                        }
                        guard deadline.timeIntervalSinceNow>0 else { throw MusicError.message("LX 音源解析总时限已到") }
                        if candidate.source==nil && !cloudEnabled { throw MusicError.message("云端音源已关闭") }
                        cooldown.removeValue(forKey:candidate.key)
                        preferred[platform]=candidate.key
                        return url
                    } catch is CancellationError { throw CancellationError() }
                    catch { last="\(name) · \(q)：\(String(error.localizedDescription.prefix(160)))" }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { last="\(name)：\(String(error.localizedDescription.prefix(160)))" }
            cooldown[candidate.key]=Date().addingTimeInterval(60)
            if preferred[platform]==candidate.key { preferred.removeValue(forKey:platform) }
        }
        if allowRefresh,cloudEnabled,!refreshingIndex,deadline.timeIntervalSinceNow>6,
           Date().timeIntervalSince(cloudAttemptedAt)>60 {
            // A stale index or changed script can be the cause even with a valid
            // old cache. Try a fresh HTTPS index once; never loop refreshes.
            let oldEntries=indexEntries
            await refreshIndex(indexURL)
            try Task.checkCancellation()
            if indexEntries != oldEntries || indexStatus.hasPrefix("已发现") {
                cloudScripts.removeAll()
                return try await resolve(track,quality:quality,excluding:excluding,deadline:deadline,allowRefresh:false)
            }
        }
        throw MusicError.message(deadline.timeIntervalSinceNow<=0 ? "音源解析超时：\(last)" : last)
    }
}
