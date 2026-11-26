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
    private var cooldown:[UUID:Date]=[:]
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
    func remove(_ id:UUID) { save(sources.filter{$0.id != id});cooldown.removeValue(forKey:id) }
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
        if enabled { cooldown.removeValue(forKey:id) }
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
        cooldown.removeValue(forKey:candidate.id)
        return candidate
    }
    func recheck(_ id:UUID) async {
        guard let source=sources.first(where:{$0.id==id}) else { return }
        do {
            let verified=try await self.checked(source,enableIfValid:source.enabled)
            var list=sources
            guard let i=list.firstIndex(where:{$0.id==id && $0.script==source.script}) else { return }
            list[i]=verified;try persist(list);cooldown.removeValue(forKey:id)
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
    func resolve(_ track:Track,quality:String,excluding:Set<String>,deadline:Date) async throws -> URL {
        cooldown=cooldown.filter{$0.value>Date()}
        let enabled=sources.filter{$0.enabled}
        // Preserve user priority; recently failing sources go after healthy ones.
        let ordered=enabled.filter{cooldown[$0.id]==nil}+enabled.filter{cooldown[$0.id] != nil}
        var last="没有已启用的 LX 音源"
        for source in ordered.prefix(12) {
            try Task.checkCancellation()
            if deadline.timeIntervalSinceNow<=0 { break }
            let runtime=LXRuntime()
            defer { runtime.close() }
            do {
                let supported=try await runtime.initialize(source,timeout:min(8,max(0.1,deadline.timeIntervalSinceNow)))
                let offered=LXProtocol.order(quality,supported:supported[track.platform.rawValue] ?? [])
                guard !offered.isEmpty else {
                    last="\(source.name) 不支持 \(track.platform.title) 的所选音质";continue
                }
                for q in offered {
                    try Task.checkCancellation()
                    if deadline.timeIntervalSinceNow<=0 { break }
                    do {
                        let address=try await runtime.resolve(track,quality:q,timeout:min(10,max(0.1,deadline.timeIntervalSinceNow)))
                        guard !excluding.contains(address) else { throw MusicError.message("音源返回已失败的旧播放链接") }
                        let url=try await LXNetwork.checked(address)
                        guard deadline.timeIntervalSinceNow>0 else { throw MusicError.message("LX 音源解析总时限已到") }
                        cooldown.removeValue(forKey:source.id)
                        return url
                    } catch is CancellationError { throw CancellationError() }
                    catch { last="\(source.name) · \(q)：\(String(error.localizedDescription.prefix(160)))" }
                }
                cooldown[source.id]=Date().addingTimeInterval(60)
            } catch is CancellationError { throw CancellationError() }
            catch { cooldown[source.id]=Date().addingTimeInterval(60);last="\(source.name)：\(String(error.localizedDescription.prefix(160)))" }
        }
        throw MusicError.message(last)
    }
}
