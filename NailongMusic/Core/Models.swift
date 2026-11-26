import Foundation

enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case wy, tx, kg, kw, mg, local
    static let online: [Self] = [.wy, .tx, .kg, .kw, .mg]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wy: return "网易云音乐"
        case .tx: return "QQ音乐"
        case .kg: return "酷狗音乐"
        case .kw: return "酷我音乐"
        case .mg: return "咪咕音乐"
        case .local: return "本地音乐"
        }
    }
}
struct Track: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var artist: String
    var platform: Platform
    var cover: String = ""
    var playableUri: String = ""
    var duration: Int64 = 0  // Android backup uses milliseconds
    var extra: String = "{}"
    var key: String { "\(platform.rawValue):\(id)" }
    var metadata: [String: String] {
        let object = (try? JSONSerialization.jsonObject(with: Data(extra.utf8))) as? [String: Any] ?? [:]
        return object.compactMapValues { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
    }
    func portable() -> Self {
        var copy = self
        copy.playableUri = ""
        let allowed = Set(["songmid","songId","strMediaMid","albumMid","albumId","albumName","hash","audioId","copyrightId","name","singer","source","types","_types","interval","lrcUrl","mrcUrl","trcUrl","img"])
        let object = (try? JSONSerialization.jsonObject(with: Data(extra.utf8))) as? [String: Any] ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: object.filter { allowed.contains($0.key) }),
           let text = String(data: data, encoding: .utf8) { copy.extra = text } else { copy.extra = "{}" }
        return copy
    }
}
struct MusicCollection: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var platform: Platform
    var kind: String = "PLAYLIST"
    var cover: String = ""
    var subtitle: String = ""
    var key: String { "\(platform.rawValue):\(kind):\(id)" }
    var isLocal: Bool { id.hasPrefix("local-") && kind == "PLAYLIST" }
}
struct PlaylistSnapshot: Codable, Hashable, Identifiable, Sendable {
    var collection: MusicCollection
    var tracks: [Track]
    var id: String { collection.key }
}
struct ListeningRecord: Codable, Hashable, Sendable {
    var day: String
    var hour: Int
    var key: String
    var title: String
    var artist: String
    var platform: String
    var millis: Int64
    var plays: Int
}
struct PreferredSource: Codable, Hashable, Sendable {
    var originalKey: String
    var track: Track
}
struct LibraryBackup: Codable, Sendable {
    var type = "nailong.music.library"
    var version = 4
    var exportedAt = Int64(Date().timeIntervalSince1970 * 1000)
    var favorites: [Track] = []
    var recent: [Track] = []
    var playlists: [MusicCollection] = []
    var searches: [String] = []
    var statistics: [ListeningRecord]? = []
    var preferredSources: [PreferredSource]? = []
    var localPlaylists: [PlaylistSnapshot]? = []
    // Mutate a local copy before writing back to avoid overlapping inout access.
    mutating func addTrack(_ track: Track, toPlaylist id: String) {
        guard var lists = localPlaylists,
              let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].tracks = (lists[index].tracks + [track]).uniqueTracks()
        localPlaylists = lists
    }
    func validated() throws -> Self {
        guard type == "nailong.music.library", (1...4).contains(version),
              favorites.count <= 10000, recent.count <= 10000, playlists.count <= 10000,
              searches.count <= 30, (localPlaylists?.count ?? 0) <= 200,
              (statistics?.count ?? 0) <= 120000, (preferredSources?.count ?? 0) <= 2000 else {
            throw MusicError.message("不支持的备份格式或数量超限")
        }
        let tracks = favorites + recent + (localPlaylists ?? []).flatMap(\.tracks) + (preferredSources ?? []).map(\.track)
        let collections = playlists + (localPlaylists ?? []).map(\.collection)
        guard tracks.count <= 50000, tracks.allSatisfy({
            !$0.id.isEmpty && $0.id.count <= 2048 && !$0.title.isEmpty && $0.title.count <= 2048 &&
            $0.extra.utf8.count <= 65536 && (0...86400000).contains($0.duration)
        }), collections.allSatisfy({
            !$0.name.isEmpty && $0.name.count <= 2048 &&
            $0.id.range(of: #"^[A-Za-z0-9_-]{1,96}$"#, options: .regularExpression) != nil
        }), searches.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
        (statistics ?? []).allSatisfy({ (0...23).contains($0.hour) && (0...86400000).contains($0.millis) &&
            (0...100000).contains($0.plays) }) else { throw MusicError.message("备份数据无效") }
        var result = self
        result.favorites = favorites.map { $0.portable() }.uniqueTracks()
        result.recent = recent.map { $0.portable() }.uniqueTracks()
        result.localPlaylists = localPlaylists?.map {
            PlaylistSnapshot(collection: $0.collection, tracks: $0.tracks.map { $0.portable() }.uniqueTracks())
        }
        result.preferredSources = preferredSources?.map { PreferredSource(originalKey: $0.originalKey, track: $0.track.portable()) }
        return result
    }
}
enum PlayMode: String, CaseIterable, Codable, Identifiable {
    case order, repeatAll, repeatOne, shuffle
    var id: String { rawValue }
    var title: String {
        switch self { case .order: return "顺序"; case .repeatAll: return "列表循环"; case .repeatOne: return "单曲循环"; case .shuffle: return "随机" }
    }
    var symbol: String {
        switch self { case .order: return "list.number"; case .repeatAll: return "repeat"; case .repeatOne: return "repeat.1"; case .shuffle: return "shuffle" }
    }
    func next(current: Int, count: Int, automatic: Bool) -> Int? {
        guard count > 0, (0..<count).contains(current) else { return nil }
        switch self {
        case .repeatOne where automatic: return current
        case .shuffle: return count == 1 ? (automatic ? 0 : nil) : (0..<count).filter { $0 != current }.randomElement()
        default: return current + 1 < count ? current + 1 : (self == .repeatAll ? 0 : nil)
        }
    }
}
enum MusicError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
extension Array where Element == Track {
    func uniqueTracks() -> [Track] {
        var seen = Set<String>()
        return filter { seen.insert($0.key).inserted }
    }
}
func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < 100000000 else { return "0:00" }
    let value = Int(seconds)
    return String(format: "%d:%02d", value / 60, value % 60)
}
