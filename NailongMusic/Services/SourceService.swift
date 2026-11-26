import Foundation
import SwiftUI

struct SourceConfiguration: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var endpoint: String
}
@MainActor final class Settings: ObservableObject {
    let lxStore = LXSourceStore()
    @AppStorage("theme") var theme: String = "system" { willSet { objectWillChange.send() } }
    @AppStorage("quality") var quality: String = "320k" { willSet { objectWillChange.send() } }
    @AppStorage("pauseRoute") var pauseRoute: Bool = true
    @AppStorage("mix") var mix: Bool = false
    @AppStorage("translation") var translation: Bool = true { willSet { objectWillChange.send() } }
    @AppStorage("analyticsEnabled") var analyticsEnabled:Bool=true { willSet { objectWillChange.send() } }
    @AppStorage("saveSearch") var saveSearch: Bool = true
    @AppStorage("rememberProgress") var rememberProgress: Bool = true
    @AppStorage("autoRoute") var autoRoute: Bool = true
    @AppStorage("service") var service: String = "https://music.20110208.xyz/cm/" { willSet { objectWillChange.send() } }
    @AppStorage("sourceData") private var sourceData = Data()
    @Published private(set) var sources: [SourceConfiguration] = []
    @Published var routeStatus = ""
    static let routes = ["https://music.20110208.xyz/cm/","https://cm.bileizhen.top/cm/","https://currentmusic.geekertao.com/cm/","https://music.ctcehs.com/cm/"]
    init() { sources = (try? JSONDecoder().decode([SourceConfiguration].self,from:sourceData)) ?? [] }
    var colorScheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    func addSource(name: String, endpoint: String) throws {
        _ = try LXProtocol.httpsURL(endpoint)
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw MusicError.message("请输入音源名称") }
        guard sources.count < 20 else { throw MusicError.message("最多 20 个音源") }
        sources.append(.init(name:name,endpoint:endpoint))
        saveSources()
    }
    func remove(_ index: IndexSet) { sources.remove(atOffsets:index); saveSources() }
    func move(_ from: IndexSet, to: Int) { sources.move(fromOffsets:from,toOffset:to); saveSources() }
    private func saveSources() { if let data = try? JSONEncoder().encode(sources) { sourceData = data } }
    func measure() async {
        routeStatus = "正在测速…"
        let urls = autoRoute ? Self.routes : [Self.routes[0]]
        let results = await withTaskGroup(of: (String,Int?).self, returning: [(String,Int?)].self) { group in
            for base in urls {
                group.addTask {
                    let start = Date()
                    do {
                        _ = try await WebClient.json(base + "announcements",["limit":"1"])
                        return (base,Int(Date().timeIntervalSince(start)*1000))
                    } catch { return (base,nil) }
                }
            }
            var values: [(String,Int?)] = []
            for await value in group { values.append(value) }
            return values
        }
        if let fastest = results.filter({ $0.1 != nil }).min(by:{ ($0.1 ?? .max) < ($1.1 ?? .max) }) {
            service = fastest.0; routeStatus = "HTTP 往返 \(fastest.1 ?? 0) ms"
        } else { routeStatus = "线路探测失败，保留原设置" }
    }
}
enum SourceService {
    // LX UserApi v2 first, optional user-configured JSON service as fallback.
    // POST {platform, id, title, artist, quality, metadata}; response {url, lyrics?}.
    struct Resolved { let url: URL; let lyrics: String?; let sourceTrack:Track }
    @MainActor static func resolve(_ track: Track, quality: String, sources: [SourceConfiguration], lxStore: LXSourceStore, excluding: Set<String> = [],deadline:Date=Date().addingTimeInterval(45)) async throws -> Resolved {
        let qualities = ["flac24bit","flac","320k","128k"]
        let start = qualities.firstIndex(of:quality) ?? 2
        var last = "请在「设置 → 音源与网络 → LX 音源管理」启用可信云端音源或导入授权脚本，也可导入本地音频。"
        if lxStore.cloudEnabled || lxStore.sources.contains(where:{$0.enabled}) {
            do {
                let url = try await lxStore.resolve(track,quality:quality,excluding:excluding,deadline:deadline)
                return .init(url:url,lyrics:nil,sourceTrack:track)
            } catch is CancellationError { throw CancellationError() }
            catch { last = error.localizedDescription }
        }
        for source in sources {
            for q in qualities[start...] {
                if Date() > deadline { throw MusicError.message("音源解析超时：\(last)") }
                try Task.checkCancellation()
                do {
                    let payload: JSON = ["platform":track.platform.rawValue,"id":track.id,"title":track.title,"artist":track.artist,"quality":q,"metadata":track.metadata]
                    let data=try JSONSerialization.data(withJSONObject:payload)
                    let reply=try await LXNetwork.fetch(source.endpoint,method:"POST",headers:["Content-Type":"application/json","Accept":"application/json"],body:data,timeout:min(12,max(1,deadline.timeIntervalSinceNow)),maxBytes:2*1024*1024)
                    guard (200..<300).contains(reply.status),let response=try JSONSerialization.jsonObject(with:reply.data) as? JSON else { throw MusicError.message("JSON 音源响应无效（HTTP \(reply.status)）") }
                    guard let text = response["url"] as? String, !excluding.contains(text) else { throw MusicError.message("音源未提供新的可播放地址") }
                    let url = try await LXNetwork.checked(text,allowHTTP:true)
                    guard !excluding.contains(url.absoluteString) else { throw MusicError.message("音源返回已失败的旧播放链接") }
                    return .init(url:url,lyrics:response["lyrics"] as? String,sourceTrack:track)
                } catch is CancellationError { throw CancellationError() }
                catch { last = "\(source.name)：\(error.localizedDescription)" }
            }
        }
        throw MusicError.message(last)
    }
    // Prefer a previously verified equivalent; only search other platforms
    // after all configured authorized resolvers fail for the original song.
    @MainActor static func resolvePlayback(_ original:Track,preferred:Track?,quality:String,sources:[SourceConfiguration],lxStore:LXSourceStore,excluding:Set<String>) async throws -> Resolved {
        let overall=Date().addingTimeInterval(100)
        let hasSource=lxStore.cloudEnabled || lxStore.sources.contains{$0.enabled} || !sources.isEmpty
        var last="没有可用音源"
        var attempted=Set<String>()
        var initial=[original]
        if let preferred,TrackMatch.verified(original,preferred) { initial.insert(preferred,at:0) }
        for track in initial {
            attempted.insert(track.key)
            try Task.checkCancellation()
            do {
                let slice=track.key==original.key ? 40.0 : 18.0
                return try await resolve(track,quality:quality,sources:sources,lxStore:lxStore,excluding:excluding,deadline:min(overall,Date().addingTimeInterval(slice)))
            } catch is CancellationError { throw CancellationError() }
            catch { last=error.localizedDescription }
        }
        guard hasSource,original.duration>0,overall.timeIntervalSinceNow>0 else { throw MusicError.message(last) }
        let candidates=await withTaskGroup(of:(Platform,[Track]).self,returning:[Track].self) { group in
            for platform in Platform.online where platform != original.platform {
                group.addTask {
                    let page=try? await Catalog.search(platform,"\(original.title) \(original.artist)")
                    return (platform,Array((page?.items ?? []).filter{TrackMatch.verified(original,$0)}.prefix(2)))
                }
            }
            var results:[Platform:[Track]]=[:]
            for await (platform,tracks) in group { results[platform]=tracks }
            return Platform.online.flatMap{results[$0] ?? []}
        }
        try Task.checkCancellation()
        for track in candidates.prefix(8) where attempted.insert(track.key).inserted {
            if overall.timeIntervalSinceNow<=0 { break }
            do {
                return try await resolve(track,quality:quality,sources:sources,lxStore:lxStore,excluding:excluding,deadline:min(overall,Date().addingTimeInterval(18)))
            } catch is CancellationError { throw CancellationError() }
            catch { last="\(track.platform.title) 匹配版本：\(error.localizedDescription)" }
        }
        throw MusicError.message("音源解析未成功：\(last)")
    }
}
