import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

@MainActor final class Player: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = -1
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var lyricError = ""
    @Published var error: String?
    @Published var mode: PlayMode = .order { didSet { UserDefaults.standard.set(mode.rawValue,forKey:"playMode") } }
    let engine = AVPlayer()
    private let library: Library
    private let settings: Settings
    private var timeObserver: Any?
    private var itemStatus: NSKeyValueObservation?
    private var controlStatus: NSKeyValueObservation?
    private var itemEnd: NSObjectProtocol?
    private var itemFailure: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var loadTask: Task<Void,Never>?
    private var lyricTask: Task<Void,Never>?
    private var artTask: Task<Void,Never>?
    private var generation = UUID()
    private var rejected = Set<String>()
    private var retryCount = 0
    private var currentURL: URL?
    private var pendingAlternate:Track?
    private var pendingMillis: Int64 = 0
    private var recordedPosition: Double?
    private var counted = false
    private var desiredPlay = false
    private var resumeAfterInterrupt = false
    private var nowArtwork: MPMediaItemArtwork?
    private var lastProgressSave: Date = .distantPast
    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    struct Resume: Codable { var track: Track; var position: Double }
    init(library: Library, settings: Settings) {
        self.library = library; self.settings = settings
        mode = PlayMode(rawValue:UserDefaults.standard.string(forKey:"playMode") ?? "") ?? .order
        engine.automaticallyWaitsToMinimizeStalling = true
        timeObserver = engine.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.2,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        controlStatus = engine.observe(\.timeControlStatus,options:[.initial,.new]) { [weak self] _,_ in
            Task { @MainActor in
                guard let self else { return }
                self.playing = self.engine.timeControlStatus == .playing
                self.updateNowPlaying()
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, self?.settings.pauseRoute == true { self?.pause() } }
        })
        observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterrupt = self.desiredPlay; self.pause()
                } else if self.resumeAfterInterrupt && AVAudioSession.InterruptionOptions(rawValue:options).contains(.shouldResume) {
                    self.resumeAfterInterrupt = false; self.resume()
                }
            }
        })
        observers.append(center.addObserver(forName:UIApplication.didEnterBackgroundNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.flush(); self?.saveProgress(force:true) }
        })
        installRemoteCommands()
        if settings.rememberProgress,
           let bytes = UserDefaults.standard.data(forKey:"resume"),
           let saved = try? JSONDecoder().decode(Resume.self,from:bytes) {
            queue = [saved.track]; index = 0; position = max(0,saved.position); duration = Double(saved.track.duration)/1000
        }
    }
    private func activate() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback,mode:.default,options:settings.mix ? [.mixWithOthers] : [])
        try audio.setActive(true)
    }
    func play(_ track: Track, in list: [Track]? = nil) {
        flush()
        queue = (list ?? [track]).uniqueTracks()
        if !queue.contains(where:{$0.key == track.key}) { queue.insert(track,at:0) }
        index = queue.firstIndex(where:{$0.key == track.key}) ?? 0
        start()
    }
    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        flush(); index = i; start()
    }
    func addNext(_ track: Track) {
        if let existing = queue.firstIndex(where:{$0.key == track.key}) {
            if existing == index { return }
            queue.remove(at:existing)
            if existing < index { index -= 1 }
        }
        queue.insert(track,at:min(index+1,queue.count))
        if index < 0 { index = 0 }
    }
    func enqueue(_ track: Track) {
        guard !queue.contains(where:{$0.key == track.key}) else { return }
        queue.append(track)
        if index < 0 { index = 0 }
    }
    func delete(_ offsets: IndexSet) {
        guard !offsets.contains(index) else { error = "无法删除正在选择的歌曲，请先切歌。"; return }
        index -= offsets.filter { $0 < index }.count
        queue.remove(atOffsets:offsets)
    }
    func next(automatic: Bool = false) {
        guard let target = mode.next(current:index,count:queue.count,automatic:automatic) else {
            pause(); return
        }
        if target == index && automatic {
            flush(); counted = false; seek(0); resume()
        } else { playAt(target) }
    }
    func previous() {
        guard current != nil else { return }
        if position > 3 { seek(0); return }
        if index > 0 { playAt(index-1) }
        else if mode == .repeatAll && queue.count > 1 { playAt(queue.count-1) }
        else { seek(0) }
    }
    func toggle() { if desiredPlay { pause() } else { resume() } }
    func pause() {
        desiredPlay = false
        engine.pause()
        playing = false
        flush(); saveProgress(force:true); updateNowPlaying()
    }
    func resume() {
        guard current != nil else { return }
        if engine.currentItem == nil { start(resumeAt:position); return }
        do { try activate(); desiredPlay = true; engine.play(); updateNowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let target = max(0,min(duration > 0 ? duration : seconds,seconds))
        recordedPosition = nil
        position = target
        engine.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        updateNowPlaying(); saveProgress(force:true)
    }
    func importLyrics(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard current != nil else { throw MusicError.message("请先选择一首歌曲") }
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 1024*1024 else { throw MusicError.message("歌词文件过大") }
            let raw = try String(contentsOf:url,encoding:.utf8)
            let result = Lyrics.parse(raw)
            guard !result.isEmpty else { throw MusicError.message("没有有效歌词时间戳") }
            lyricTask?.cancel(); lines = result; lyricError = ""
        } catch { self.error = error.localizedDescription }
    }
    private func start(resumeAt: Double = 0, recovery: Bool = false) {
        guard let track = current else { return }
        loadTask?.cancel(); lyricTask?.cancel(); artTask?.cancel()
        generation = UUID()
        let ticket = generation
        clearItem()
        desiredPlay = true; loading = true; playing = false; position = resumeAt
        duration = Double(track.duration)/1000
        if !recovery {
            rejected = []; retryCount = 0; counted = false
            lines = []; lyricError = ""; nowArtwork = nil
        }
        recordedPosition = nil; error = nil; currentURL = nil; pendingAlternate=nil
        updateNowPlaying()
        let sources = settings.sources, quality = settings.quality, service = settings.service
        let preferred = library.data.preferredSources?.first(where:{$0.originalKey == track.key})?.track
        if !recovery {
            lyricTask = Task { [weak self] in
                do {
                    let result = try await Catalog.lyrics(track,service:service)
                    guard let self, self.generation == ticket, !Task.isCancelled, self.lines.isEmpty else { return }
                    self.lines = result; self.lyricError = result.isEmpty ? "暂无歌词" : ""
                } catch {
                    guard let self, self.generation == ticket, !Task.isCancelled, self.lines.isEmpty else { return }
                    self.lyricError = error.localizedDescription
                }
            }
            if let url = URL(string:track.cover), url.scheme == "https" {
                artTask = Task { [weak self] in
                    if let data = try? await WebClient.data(url,maxBytes:5*1024*1024), let image = UIImage(data:data),
                       let self, self.generation == ticket, !Task.isCancelled {
                        self.nowArtwork = MPMediaItemArtwork(boundsSize:image.size) { _ in image }; self.updateNowPlaying()
                    }
                }
            }
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url: URL
                var suppliedLyrics: String?
                if track.platform == .local {
                    if track.playableUri.hasPrefix("https://") {
                        url = try await LXNetwork.checked(track.playableUri)
                    } else {
                        guard let local = self.library.localURL(track) else { throw MusicError.message("本地音频不存在，请重新导入。") }
                        url = local
                    }
                } else {
                    let result=try await SourceService.resolvePlayback(track,preferred:preferred,quality:quality,sources:sources,lxStore:self.settings.lxStore,excluding:self.rejected)
                    guard self.generation==ticket,!Task.isCancelled else { return }
                    url=result.url; suppliedLyrics=result.lyrics
                    self.pendingAlternate=TrackMatch.verified(track,result.sourceTrack) ? result.sourceTrack.portable() : nil
                }
                guard self.generation == ticket, !Task.isCancelled else { return }
                if let suppliedLyrics {
                    let parsed = Lyrics.parse(suppliedLyrics)
                    if !parsed.isEmpty { self.lines = parsed; self.lyricError = ""; self.lyricTask?.cancel() }
                }
                try self.activate()
                self.currentURL = url
                self.prepare(url,ticket:ticket,resumeAt:resumeAt)
            } catch {
                guard self.generation == ticket, !Task.isCancelled else { return }
                self.loading = false; self.desiredPlay = false; self.error = error.localizedDescription
            }
        }
    }
    private func prepare(_ url: URL, ticket: UUID, resumeAt: Double) {
        let item = AVPlayerItem(url:url)
        engine.replaceCurrentItem(with:item)
        itemStatus = item.observe(\.status,options:[.initial,.new]) { [weak self] _,_ in
            Task { @MainActor in
                guard let self, self.generation == ticket, let item = self.engine.currentItem else { return }
                if item.status == .readyToPlay {
                    self.loading = false
                    if item.duration.seconds.isFinite && item.duration.seconds > 0 { self.duration = item.duration.seconds }
                    self.updateNowPlaying()
                    if resumeAt > 0 { self.seek(resumeAt) }
                    if self.desiredPlay { self.engine.play() }
                } else if item.status == .failed { self.failed(item.error?.localizedDescription ?? "音频加载失败") }
            }
        }
        itemEnd = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in
            Task { @MainActor in guard let self,self.generation == ticket else { return }; self.next(automatic:true) }
        }
        itemFailure = NotificationCenter.default.addObserver(forName:.AVPlayerItemFailedToPlayToEndTime,object:item,queue:.main) { [weak self] _ in
            Task { @MainActor in guard let self,self.generation == ticket else { return }; self.failed("音频流播放中断") }
        }
        if desiredPlay { engine.play() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds:25_000_000_000)
            guard let self, self.generation == ticket,self.loading,self.engine.currentItem?.status != .readyToPlay else { return }
            self.failed("音频加载超时")
        }
    }
    private func failed(_ message: String) {
        guard current != nil, engine.currentItem != nil else { return }
        let shouldRetry = desiredPlay && current?.platform != .local && retryCount < 2
        if let url = currentURL { rejected.insert(url.absoluteString) }
        flush()
        if shouldRetry {
            retryCount += 1; start(resumeAt:position,recovery:true)
        } else {
            clearItem(); loading = false; desiredPlay = false; playing = false; error = message; updateNowPlaying()
        }
    }
    private func clearItem() {
        itemStatus?.invalidate(); itemStatus = nil
        if let itemEnd { NotificationCenter.default.removeObserver(itemEnd) }; itemEnd = nil
        if let itemFailure { NotificationCenter.default.removeObserver(itemFailure) }; itemFailure = nil
        engine.pause(); engine.replaceCurrentItem(with:nil)
    }
    private func tick(_ value: Double) {
        guard current != nil, engine.currentItem != nil else { return }
        if value.isFinite { position = max(0,value) }
        if let seconds = engine.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { duration = seconds }
        if engine.timeControlStatus == .playing, let track = current {
            if let alternate=pendingAlternate {
                pendingAlternate=nil
                library.change { backup in
                    var rows=backup.preferredSources ?? []
                    rows.removeAll{$0.originalKey==track.key}
                    rows.insert(.init(originalKey:track.key,track:alternate),at:0)
                    backup.preferredSources=Array(rows.prefix(2000))
                }
            }
            if !counted { counted = true; library.recent(track); library.addListening(track,millis:0,plays:1) }
            if let previous = recordedPosition {
                let delta = value-previous
                if delta > 0 && delta < 1.5 { pendingMillis += Int64(delta*1000) }
            }
            recordedPosition = value.isFinite ? value : nil
            if pendingMillis >= 15000 { flush() }
            saveProgress()
        } else { recordedPosition = nil }
    }
    private func flush() {
        if let track = current, pendingMillis > 0 { library.addListening(track,millis:pendingMillis) }
        pendingMillis = 0; recordedPosition = nil
    }
    private func saveProgress(force: Bool = false) {
        guard settings.rememberProgress else { UserDefaults.standard.removeObject(forKey:"resume"); return }
        guard let current, force || Date().timeIntervalSince(lastProgressSave) > 8 else { return }
        lastProgressSave = Date()
        if let bytes = try? JSONEncoder().encode(Resume(track:current,position:position)) { UserDefaults.standard.set(bytes,forKey:"resume") }
    }
    private func updateNowPlaying() {
        guard let track = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String:Any] = [MPMediaItemPropertyTitle:track.title,MPMediaItemPropertyArtist:track.artist,
                                 MPNowPlayingInfoPropertyElapsedPlaybackTime:position,MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0 : 0.0]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let album = track.metadata["albumName"] { info[MPMediaItemPropertyAlbumTitle] = album }
        if let nowArtwork { info[MPMediaItemPropertyArtwork] = nowArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func installRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in self?.seek(position) }; return .success
        }
    }
}
