import Foundation
import SwiftUI

@MainActor final class Library: ObservableObject {
    @Published private(set) var data = LibraryBackup()
    @Published var error: String?
    private let file: URL
    private var readFailed = false
    let localDirectory: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NailongMusic", isDirectory: true)
        file = base.appendingPathComponent("library.json")
        localDirectory = base.appendingPathComponent("Audio", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: file))
            }
        } catch { readFailed = true; self.error = "读取音乐库失败，原文件已保留：\(error.localizedDescription)" }
    }
    func change(_ edit: (inout LibraryBackup) -> Void) {
        guard !readFailed else { error = "原音乐库读取失败，请通过备份管理恢复有效备份。"; return }
        var copy = data
        edit(&copy)
        do {
            try JSONEncoder().encode(copy).write(to: file, options: .atomic)
            data = copy
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func isFavorite(_ track: Track) -> Bool { data.favorites.contains { $0.key == track.key } }
    func toggle(_ track: Track) { change { d in
        if d.favorites.contains(where: { $0.key == track.key }) { d.favorites.removeAll { $0.key == track.key } }
        else { d.favorites.insert(track, at: 0) }
    } }
    func toggle(_ collection: MusicCollection) { change { d in
        if d.playlists.contains(where: { $0.key == collection.key }) { d.playlists.removeAll { $0.key == collection.key } }
        else { d.playlists.insert(collection, at: 0) }
    } }
    func recent(_ track: Track) { change { d in
        d.recent.removeAll { $0.key == track.key }; d.recent.insert(track, at: 0); d.recent = Array(d.recent.prefix(500))
    } }
    func remember(_ word: String) { change { d in
        d.searches.removeAll { $0 == word }; d.searches.insert(String(word.prefix(80)), at: 0); d.searches = Array(d.searches.prefix(30))
    } }
    func create(_ name: String, tracks: [Track] = []) {
        let collection = MusicCollection(id: "local-\(UUID().uuidString)", name: name, platform: tracks.first(where: { $0.platform != .local })?.platform ?? .wy)
        change { $0.localPlaylists = ($0.localPlaylists ?? []) + [.init(collection: collection, tracks: tracks.uniqueTracks())] }
    }
    func add(_ track: Track, to id: String) { change { d in
        guard let index = d.localPlaylists?.firstIndex(where: { $0.id == id }) else { return }
        d.localPlaylists?[index].tracks = ((d.localPlaylists?[index].tracks ?? []) + [track]).uniqueTracks()
    } }
    func deletePlaylist(_ id: String) { change { $0.localPlaylists?.removeAll { $0.id == id } } }
    func remove(_ track: Track, from id: String) { change { d in
        guard let index = d.localPlaylists?.firstIndex(where: { $0.id == id }) else { return }
        d.localPlaylists?[index].tracks.removeAll { $0.key == track.key }
    } }
    func localURL(_ track: Track) -> URL? {
        guard track.platform == .local, !track.playableUri.isEmpty,
              track.playableUri == URL(fileURLWithPath: track.playableUri).lastPathComponent else { return nil }
        let url = localDirectory.appendingPathComponent(track.playableUri)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func importAuthorizedURL(name: String, address: String) throws {
        let url = try WebClient.url(address)
        let title = name.trimmingCharacters(in:.whitespacesAndNewlines).nonEmpty ?? url.deletingPathExtension().lastPathComponent.nonEmpty ?? "授权音频"
        let track = Track(id:UUID().uuidString,title:String(title.prefix(200)),artist:"自有或授权音频",platform:.local,playableUri:url.absoluteString)
        create("授权音频 · \(track.title)",tracks:[track])
    }
    func importAudio(_ urls: [URL]) {
        var imported: [Track] = []
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let id = UUID().uuidString
                let filename = "\(id).\(url.pathExtension)"
                let destination = localDirectory.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: url, to: destination)
                imported.append(.init(id: id, title: url.deletingPathExtension().lastPathComponent, artist: "本地文件",
                                      platform: .local, playableUri: filename))
            } catch { self.error = "导入 \(url.lastPathComponent) 失败：\(error.localizedDescription)" }
        }
        if !imported.isEmpty { create("本地音乐 · \(Date().formatted(date: .abbreviated, time: .shortened))", tracks: imported) }
    }
    func addListening(_ track: Track, millis: Int64, plays: Int = 0) {
        guard millis > 0 || plays > 0 else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date()), hour = Calendar.current.component(.hour, from: Date())
        change { d in
            var records = d.statistics ?? []
            if let index = records.firstIndex(where: { $0.key == track.key && $0.day == day && $0.hour == hour }) {
                records[index].millis += millis; records[index].plays += plays
            } else {
                records.append(.init(day: day, hour: hour, key: track.key, title: track.title, artist: track.artist,
                                     platform: track.platform.rawValue, millis: millis, plays: plays))
            }
            d.statistics = Array(records.suffix(120000))
        }
    }
    func exportBackup() throws -> Data {
        var copy = data
        copy.version = 4
        copy.exportedAt = Int64(Date().timeIntervalSince1970 * 1000)
        // Android does not have a "local" platform enum. Export only portable online metadata.
        copy.favorites = copy.favorites.filter { $0.platform != .local }
        copy.recent = copy.recent.filter { $0.platform != .local }
        copy.playlists = copy.playlists.filter { $0.platform != .local }
        copy.statistics = (copy.statistics ?? []).filter { $0.platform != Platform.local.rawValue }
        copy.preferredSources = (copy.preferredSources ?? []).filter { $0.track.platform != .local && !$0.originalKey.hasPrefix("local:") }
        copy.localPlaylists = (copy.localPlaylists ?? []).map { snapshot in
            var c = snapshot.collection
            if c.platform == .local { c.platform = .wy }
            return PlaylistSnapshot(collection:c,tracks:snapshot.tracks.filter { $0.platform != .local })
        }
        copy = try copy.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(copy)
        guard bytes.count <= 32 * 1024 * 1024 else { throw MusicError.message("备份大于 32 MiB") }
        return bytes
    }
    func readBackup(_ url: URL) throws -> LibraryBackup {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw MusicError.message("备份大于 32 MiB") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 32 * 1024 * 1024 else { throw MusicError.message("备份大于 32 MiB") }
        return try JSONDecoder().decode(LibraryBackup.self, from: bytes).validated()
    }
    func restore(_ backup: LibraryBackup) {
        let previous = readFailed
        readFailed = false
        do {
            if previous && FileManager.default.fileExists(atPath:file.path) {
                try FileManager.default.copyItem(at:file,to:file.deletingLastPathComponent().appendingPathComponent("library-corrupt-\(UUID().uuidString).json"))
            }
            try JSONEncoder().encode(backup).write(to:file,options:.atomic)
            data = backup; error = nil
        } catch { readFailed = previous; self.error = "恢复失败：\(error.localizedDescription)" }
    }
}
