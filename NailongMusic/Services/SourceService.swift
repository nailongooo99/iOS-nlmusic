import Foundation
import SwiftUI

struct SourceConfiguration: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var endpoint: String
}
@MainActor final class Settings: ObservableObject {
    @AppStorage("theme") var theme: String = "system" { willSet { objectWillChange.send() } }
    @AppStorage("quality") var quality: String = "320k" { willSet { objectWillChange.send() } }
    @AppStorage("pauseRoute") var pauseRoute: Bool = true
    @AppStorage("mix") var mix: Bool = false
    @AppStorage("translation") var translation: Bool = true { willSet { objectWillChange.send() } }
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
        _ = try WebClient.url(endpoint)
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
    // User-configured, authorized service. No embedded credentials or remote executable code.
    // POST {platform, id, title, artist, quality, metadata}; response {url, lyrics?}.
    struct Resolved { let url: URL; let lyrics: String? }
    static func resolve(_ track: Track, quality: String, sources: [SourceConfiguration], excluding: Set<String> = []) async throws -> Resolved {
        let qualities = ["flac24bit","flac","320k","128k"]
        let start = qualities.firstIndex(of:quality) ?? 2
        var last = "请在「设置 → 音源与网络」添加您有权使用的 HTTPS 音源，或导入本地音频。"
        let deadline = Date().addingTimeInterval(45)
        for source in sources {
            for q in qualities[start...] {
                if Date() > deadline { throw MusicError.message("音源解析超时：\(last)") }
                try Task.checkCancellation()
                do {
                    let payload: JSON = ["platform":track.platform.rawValue,"id":track.id,"title":track.title,"artist":track.artist,"quality":q,"metadata":track.metadata]
                    let response = try await WebClient.json(source.endpoint,method:"POST",payload:payload)
                    guard let text = response["url"] as? String, !excluding.contains(text) else { throw MusicError.message("音源未提供新的可播放地址") }
                    let url = try WebClient.url(text)
                    return .init(url:url,lyrics:response["lyrics"] as? String)
                } catch is CancellationError { throw CancellationError() }
                catch { last = "\(source.name)：\(error.localizedDescription)" }
            }
        }
        throw MusicError.message(last)
    }
}
