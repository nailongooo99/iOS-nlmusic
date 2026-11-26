import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var player: Player
    @State private var platform: Platform = .wy
    @State private var daily: [Track] = []
    @State private var charts: [MusicCollection] = []
    @State private var note = ""
    @State private var dailyError = ""
    @State private var loading = true
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:6) {
                    Text("NAILONG MUSIC").font(.caption.weight(.bold)).tracking(3).foregroundStyle(Color.accentColor)
                    Text("好音乐，慢慢听。").font(.largeTitle.bold())
                    Text("今天，也为喜欢的声音留一点时间。").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal)
                VStack(alignment:.leading,spacing:12) {
                    Text("每日推荐").font(.title2.bold()).padding(.horizontal)
                    Text("网易云音乐 · 公开新歌").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    if daily.isEmpty {
                        if loading { ProgressView().frame(maxWidth:.infinity).padding() }
                        else { EmptyMessage(title:"暂时没有推荐",detail:dailyError.nonEmpty ?? "下拉刷新重试") }
                    } else {
                        ScrollView(.horizontal,showsIndicators:false) {
                            HStack(spacing:16) {
                                ForEach(daily,id:\.key) { track in
                                    Button { player.play(track,in:daily) } label: {
                                        VStack(alignment:.leading,spacing:8) {
                                            ZStack(alignment:.trailing) {
                                                Circle().fill(Color.black.gradient).frame(width:116,height:116)
                                                    .overlay(Circle().strokeBorder(.white.opacity(0.18),lineWidth:1).padding(8))
                                                Artwork(url:track.cover,size:118,corner:14).offset(x:-27)
                                            }.frame(width:150,height:126)
                                            Text(track.title).font(.headline).lineLimit(1)
                                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(width:150,alignment:.leading).foregroundStyle(.primary)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal,16)
                        }
                    }
                }
                Text("音乐排行榜").font(.title2.bold()).padding(.horizontal)
                PlatformPicker(platform:$platform)
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                LazyVStack(alignment:.leading,spacing:15) {
                    ForEach(charts,id:\.key) { collection in CollectionRow(collection:collection) }
                }.padding(.horizontal)
            }.padding(.vertical,15)
        }
        .scrollChrome().navigationTitle("首页")
        .task {
            if daily.isEmpty { await loadDaily() }
        }
        .task(id:platform) { await loadCharts() }
        .refreshable { await loadDaily(); await loadCharts() }
    }
    private func loadDaily() async {
        loading = true; defer { loading = false }
        do { let items = try await Catalog.daily(); if !Task.isCancelled { daily = items; dailyError = "" } }
        catch { if !Task.isCancelled { dailyError = error.localizedDescription } }
    }
    private func loadCharts() async {
        let selected = platform
        charts = Catalog.baseline(selected); note = ""
        let result = await Catalog.charts(selected)
        if !Task.isCancelled && selected == platform { charts = result.items; note = result.note }
    }
}
struct PlaylistScreen: View {
    @EnvironmentObject var library: Library
    @State private var platform: Platform = .wy
    @State private var sort = "hot"
    @State private var items: [MusicCollection] = []
    @State private var note = ""
    @State private var loading = false
    @State private var page = 1
    @State private var more = false
    @State private var importing = false
    var body: some View {
        List {
            Section { PlatformPicker(platform:$platform).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section {
                if platform == .wy || platform == .tx || platform == .kw {
                    Picker("排序",selection:$sort) { Text("最热").tag("hot"); Text("最新").tag("new") }.pickerStyle(.segmented)
                }
                ForEach(items,id:\.key) { CollectionRow(collection:$0) }
                if loading { ProgressView().frame(maxWidth:.infinity) }
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if more && !loading { Button("加载更多") { Task { await load(reset:false) } } }
                if !loading && items.isEmpty { Button("重新加载") { Task { await load(reset:true) } } }
            } header: { Text("热门歌单") }
        }.scrollChrome().navigationTitle("歌单")
        .toolbar { Button { importing = true } label: { Image(systemName:"square.and.arrow.down") }.accessibilityLabel("导入公开歌单") }
        .sheet(isPresented:$importing) { ImportPlaylistScreen() }
        .task(id:"\(platform.rawValue):\(sort)") { await load(reset:true) }
        .refreshable { await load(reset:true) }
    }
    private func load(reset:Bool) async {
        let p = platform, s = sort
        if reset { page = 1; items = []; note = ""; more = false }
        let requested = reset ? 1 : page+1
        loading = true
        do {
            let result = try await Catalog.playlists(p,page:requested,sort:s)
            guard !Task.isCancelled, p == platform, s == sort else { return }
            var seen = Set<String>()
            items = (items+result.items).filter { seen.insert($0.key).inserted }; page = requested; more = result.more; note = result.note
        } catch { if !Task.isCancelled && p == platform && s == sort { note = error.localizedDescription } }
        if !Task.isCancelled && p == platform && s == sort { loading = false }
    }
}
struct ImportPlaylistScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: Library
    @State private var input = ""
    @State private var platform: Platform = .wy
    @State private var collection: MusicCollection?
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var note = ""
    @State private var title = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("公开歌单地址") {
                    TextField("分享链接或歌单 ID",text:$input,axis:.vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("数字 ID 的平台",selection:$platform) { ForEach(Platform.online) { Text($0.title).tag($0) } }
                    Button("验证并预览") { Task { await preview() } }.disabled(loading || input.isEmpty)
                    if loading { ProgressView() }
                    if !note.isEmpty { Text(note).foregroundStyle(.secondary) }
                }
                if let collection {
                    Section("预览 · \(tracks.count) 首（第一页）") {
                        TextField("歌单显示名称",text:$title)
                        ForEach(tracks.prefix(10),id:\.key) { Text($0.title) }
                        Button("保存公开歌单引用") {
                            var updated = collection
                            updated.name = title.trimmingCharacters(in:.whitespacesAndNewlines).nonEmpty ?? collection.name
                            if !library.data.playlists.contains(where:{$0.key == updated.key}) { library.toggle(updated) }
                            dismiss()
                        }
                    }
                }
            }.navigationTitle("导入歌单").analyticsPage("detail").toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
    private func preview() async {
        loading = true; collection = nil; tracks = []; note = ""; defer { loading = false }
        do {
            let c = try Catalog.importCollection(input,fallback:platform)
            let result = try await Catalog.detail(c)
            tracks = result.items; collection = c; title = c.name
        } catch { note = error.localizedDescription }
    }
}
struct CollectionScreen: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    let collection: MusicCollection
    @State private var remoteTracks: [Track] = []
    @State private var note = ""
    @State private var loading = false
    @State private var page = 1
    @State private var more = false
    var tracks: [Track] {
        if collection.isLocal { return library.data.localPlaylists?.first(where:{$0.id == collection.key})?.tracks ?? [] }
        return remoteTracks
    }
    var body: some View {
        List {
            Section {
                VStack(spacing:12) {
                    Artwork(url:collection.cover,size:168,corner:20)
                    Text(collection.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(collection.platform.title) · \(tracks.count) 首已加载").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { if let first = tracks.first { player.play(first,in:tracks) } } label: { Label("播放全部",systemImage:"play.fill") }.buttonStyle(.borderedProminent)
                        Button { if let first = tracks.randomElement() { player.mode = .shuffle; player.play(first,in:tracks) } } label: { Label("随机",systemImage:"shuffle") }.buttonStyle(.bordered)
                    }.disabled(tracks.isEmpty)
                }.frame(maxWidth:.infinity).padding(.vertical,14)
            }.listRowBackground(Color.clear)
            Section {
                ForEach(tracks,id:\.key) { track in
                    TrackRow(track:track,context:tracks).swipeActions(edge:.trailing,allowsFullSwipe:false) {
                        if collection.isLocal { Button(role:.destructive) { library.remove(track,from:collection.key) } label: { Label("移除",systemImage:"trash") } }
                        else { Button { library.toggle(track) } label: { Label("收藏",systemImage:"heart") }.tint(.pink) }
                    }
                }
                if loading { ProgressView().frame(maxWidth:.infinity) }
                if !note.isEmpty { Text(note).foregroundStyle(.secondary).font(.footnote) }
                if more && !loading { Button("加载更多") { Task { await load(reset:false) } } }
                if tracks.isEmpty && !loading && !collection.isLocal { Button("重试") { Task { await load(reset:true) } } }
            }
        }.scrollChrome().navigationTitle(collection.name).navigationBarTitleDisplayMode(.inline).analyticsPage("collection")
        .toolbar {
            if !collection.isLocal {
                Button { library.toggle(collection) } label: { Image(systemName:library.data.playlists.contains(where:{$0.key == collection.key}) ? "heart.fill" : "heart") }.accessibilityLabel("收藏歌单")
            }
        }.task(id:collection.key) { await load(reset:true) }.refreshable { await load(reset:true) }
    }
    private func load(reset:Bool) async {
        guard !collection.isLocal else { return }
        if reset { page = 1; remoteTracks = []; more = false; note = "" }
        let requested = reset ? 1 : page+1
        loading = true; defer { if !Task.isCancelled { loading = false } }
        do {
            let result = try await Catalog.detail(collection,page:requested)
            guard !Task.isCancelled else { return }
            remoteTracks = (remoteTracks+result.items).uniqueTracks(); more = result.more; page = requested
        } catch { if !Task.isCancelled { note = error.localizedDescription } }
    }
}
struct SearchScreen: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: Settings
    @State private var query = ""
    @State private var platform: Platform? = nil
    @State private var playlists = false
    @State private var results: [Track] = []
    @State private var collections: [MusicCollection] = []
    @State private var note = ""
    @State private var active = ""
    @State private var loading = false
    @State private var page = 1
    @State private var more = false
    @State private var job: Task<Void,Never>?
    @State private var ticket = UUID()
    var body: some View {
        List {
            Section {
                Picker("搜索类型",selection:$playlists) { Text("歌曲").tag(false); Text("歌单").tag(true) }.pickerStyle(.segmented)
                Picker("音乐平台",selection:$platform) {
                    Text("全部平台").tag(Optional<Platform>.none)
                    ForEach(Platform.online) { p in Text(p.title).tag(Optional(p)) }
                }
            }
            if active.isEmpty && !library.data.searches.isEmpty {
                Section("搜索历史") {
                    ForEach(library.data.searches,id:\.self) { word in Button(word) { query = word; submit() } }
                }
            }
            if !active.isEmpty {
                Section("搜索结果") {
                    if playlists { ForEach(collections,id:\.key) { CollectionRow(collection:$0) } }
                    else { ForEach(results,id:\.key) { TrackRow(track:$0,context:results) } }
                    if loading { ProgressView().frame(maxWidth:.infinity) }
                    if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    if more && !loading { Button("加载更多") { run(reset:false) } }
                    if !loading && results.isEmpty && collections.isEmpty { EmptyMessage(title:"没有搜索结果",detail:"请调整关键词或音乐平台。",symbol:"magnifyingglass") }
                }
            } else if library.data.searches.isEmpty {
                EmptyMessage(title:"寻找你喜欢的音乐",detail:"支持五个平台的歌曲及公开歌单搜索。",symbol:"magnifyingglass")
            }
        }.scrollChrome().navigationTitle("搜索")
        .searchable(text:$query,prompt:"歌曲、歌手、歌单")
        .onSubmit(of:.search) { submit() }
        .onChange(of:platform) { _ in if !active.isEmpty { run(reset:true) } }
        .onChange(of:playlists) { _ in if !active.isEmpty { run(reset:true) } }
        .toolbar { Button("搜索") { submit() }.disabled(query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        .onDisappear { job?.cancel(); loading = false }
    }
    private func submit() {
        let word = String(query.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
        guard !word.isEmpty else { return }
        active = word
        if settings.saveSearch { library.remember(word) }
        run(reset:true)
    }
    private func run(reset:Bool) {
        job?.cancel(); ticket = UUID()
        let id = ticket, q = active, selected = platform, lists = playlists
        if reset { results = []; collections = []; page = 1; more = false; note = "" }
        let requested = reset ? 1 : page+1
        loading = true
        job = Task {
            var allTracks: [Track] = [], allLists: [MusicCollection] = [], errors: [String] = []
            var hasMore = false
            for p in selected.map({[$0]}) ?? Platform.online {
                if Task.isCancelled { return }
                do {
                    if lists {
                        let response = try await Catalog.playlists(p,query:q,page:requested)
                        allLists += response.items; hasMore = hasMore || response.more
                        if !response.note.isEmpty { errors.append("\(p.title)：\(response.note)") }
                    } else {
                        let response = try await Catalog.search(p,q,page:requested)
                        allTracks += response.items; hasMore = hasMore || response.more
                        if !response.note.isEmpty { errors.append("\(p.title)：\(response.note)") }
                    }
                } catch { errors.append("\(p.title)：\(error.localizedDescription)") }
                guard !Task.isCancelled, ticket == id else { return }
                results = (results+allTracks).uniqueTracks()
                var seen = Set<String>(); collections = (collections+allLists).filter { seen.insert($0.key).inserted }
            }
            guard !Task.isCancelled, ticket == id else { return }
            page = requested; more = hasMore; note = errors.joined(separator:"\n"); loading = false
        }
    }
}
