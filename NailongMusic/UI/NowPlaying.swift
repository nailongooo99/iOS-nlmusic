import SwiftUI
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

struct SystemVolume: UIViewRepresentable {
    func makeUIView(context:Context) -> MPVolumeView { MPVolumeView(frame:.zero) }
    func updateUIView(_ uiView:MPVolumeView,context:Context) {}
}
struct NowPlayingScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: Settings
    @State private var selected = 0
    @State private var scrubbing = false
    @State private var scrub: Double = 0
    @State private var importLRC = false
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700 && geometry.size.width > geometry.size.height
            VStack(spacing:12) {
                HStack {
                    Button { dismiss() } label: { Image(systemName:"chevron.down").font(.title3.weight(.semibold)).frame(width:44,height:44) }.accessibilityLabel("收起播放器")
                    Spacer()
                    Text("正在播放").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button { importLRC = true } label: { Label("导入本地歌词",systemImage:"doc.badge.plus") }
                        if let track = player.current {
                            Button { library.toggle(track) } label: { Label(library.isFavorite(track) ? "取消收藏" : "收藏",systemImage:"heart") }
                        }
                    } label: { Image(systemName:"ellipsis.circle").font(.title2).frame(width:44,height:44) }
                }
                if wide {
                    HStack(spacing:22) {
                        VStack(spacing:12) { coverPanel(size:min(geometry.size.height*0.44,310)); controls }
                            .frame(maxWidth:geometry.size.width*0.46)
                        VStack { picker; panel(size:geometry.size.height*0.65) }
                    }
                } else {
                    panel(size:max(100,min(geometry.size.height-325,geometry.size.width-40)))
                    controls
                    picker
                }
            }.padding(.horizontal,20).padding(.vertical,6).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.center)
        }
        .background {
            ZStack {
                Color(uiColor:.systemBackground)
                if let track = player.current {
                    AsyncImage(url:URL(string:track.cover)) { image in
                        image.resizable().scaledToFill().blur(radius:55).opacity(0.20)
                    } placeholder: { Color.clear }
                }
                Color(uiColor:.systemBackground).opacity(0.45)
            }.clipped().ignoresSafeArea()
        }
        .alert("奶龙音乐",isPresented:Binding(get:{player.error != nil || library.error != nil},set:{ if !$0 { player.error = nil; library.error = nil } })) {
            Button("确定",role:.cancel) { player.error = nil; library.error = nil }
        } message: { Text(player.error ?? library.error ?? "") }
        .fileImporter(isPresented:$importLRC,allowedContentTypes:[.plainText,.data]) { result in
            switch result { case .success(let url): player.importLyrics(url); case .failure(let error): player.error = error.localizedDescription }
        }
    }
    private var picker: some View {
        Picker("播放页面",selection:$selected) {
            Label("封面",systemImage:"music.note").tag(0)
            Label("歌词",systemImage:"quote.bubble").tag(1)
            Label("评论",systemImage:"bubble.left.and.bubble.right").tag(2)
            Label("队列",systemImage:"list.bullet").tag(3)
        }.pickerStyle(.segmented).labelsHidden()
    }
    private func coverPanel(size:CGFloat) -> some View {
        Artwork(url:player.current?.cover ?? "",size:max(70,size),corner:24)
            .shadow(color:.black.opacity(0.20),radius:18,y:10)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    @ViewBuilder private func panel(size:CGFloat) -> some View {
        switch selected {
        case 1: LyricPanel().frame(maxWidth:.infinity).frame(height:size)
        case 2: CommentsPanel().frame(maxWidth:.infinity).frame(height:size)
        case 3: QueuePanel().frame(maxWidth:.infinity).frame(height:size)
        default: coverPanel(size:size).frame(height:size)
        }
    }
    private var controls: some View {
        VStack(spacing:10) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(player.current?.title ?? "未选择歌曲").font(.title2.bold()).lineLimit(2)
                    Text(player.current?.artist ?? "奶龙音乐").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let track = player.current {
                    Button { library.toggle(track) } label: { Image(systemName:library.isFavorite(track) ? "heart.fill" : "heart").font(.title2).foregroundStyle(library.isFavorite(track) ? Color.pink : Color.primary) }.accessibilityLabel("收藏")
                }
            }
            VStack(spacing:2) {
                Slider(value:Binding(get:{ scrubbing ? scrub : min(player.position,max(1,player.duration)) },set:{ scrub = $0 }),in:0...max(1,player.duration),onEditingChanged:{ editing in
                    if editing { scrub = player.position; scrubbing = true }
                    else { player.seek(scrub); scrubbing = false }
                }).disabled(player.duration <= 0)
                HStack {
                    Text(clockText(scrubbing ? scrub : player.position))
                    Spacer()
                    Text(clockText(player.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Menu {
                    ForEach(PlayMode.allCases) { mode in Button { player.mode = mode } label: {
                        if player.mode == mode { Label(mode.title,systemImage:"checkmark") }
                        else { Label(mode.title,systemImage:mode.symbol) }
                    } }
                } label: { Image(systemName:player.mode.symbol).font(.title2).frame(width:44,height:44) }.accessibilityLabel("播放模式：\(player.mode.title)")
                Spacer()
                Button { player.previous() } label: { Image(systemName:"backward.end.fill").font(.system(size:29)).frame(width:45,height:54) }.accessibilityLabel("上一首")
                Spacer()
                Button { player.toggle() } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width:66,height:66)
                        if player.loading { ProgressView().tint(.white) }
                        else { Image(systemName:player.playing ? "pause.fill" : "play.fill").font(.system(size:29,weight:.semibold)).foregroundStyle(.white) }
                    }
                }.accessibilityLabel(player.playing ? "暂停" : "播放")
                Spacer()
                Button { player.next() } label: { Image(systemName:"forward.end.fill").font(.system(size:29)).frame(width:45,height:54) }.accessibilityLabel("下一首")
                Spacer()
                Button { selected = selected == 3 ? 0 : 3 } label: { Image(systemName:"list.bullet").font(.title2).frame(width:44,height:44) }.accessibilityLabel("播放队列")
            }.buttonStyle(.plain)
            HStack {
                Image(systemName:"speaker.fill").foregroundStyle(.secondary).font(.caption)
                SystemVolume().frame(height:26)
            }
        }.padding(.vertical,5)
    }
}
struct LyricPanel: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var settings: Settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var active: Int? { Lyrics.active(player.lines,at:player.position) }
    var body: some View {
        if player.lines.isEmpty {
            EmptyMessage(title:"暂无歌词",detail:player.lyricError.nonEmpty ?? "歌词加载中；可在右上角导入 LRC 文件。",symbol:"quote.bubble")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:24) {
                        ForEach(Array(player.lines.enumerated()),id:\.offset) { index,line in
                            Button { player.seek(line.time) } label: {
                                VStack(alignment:.leading,spacing:7) {
                                    words(line,active:index == active)
                                    if settings.translation && !line.translation.isEmpty {
                                        Text(line.translation).font(.body).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                            .opacity(index == active ? 1 : 0.45)
                            .id(index)
                        }
                    }.padding(.horizontal,4).padding(.vertical,50)
                }.onChange(of:active) { index in
                    if let index { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.3)) { proxy.scrollTo(index,anchor:.center) } }
                }.onAppear { if let active { proxy.scrollTo(active,anchor:.center) } }
            }
        }
    }
    private func words(_ line:LyricLine,active:Bool) -> some View {
        let text: Text
        if active && !line.words.isEmpty {
            text = line.words.reduce(Text("")) { value,word in
                value + Text(word.text).foregroundColor(player.position >= word.start ? .primary : .secondary)
            }
        } else { text = Text(line.text) }
        return text.font(.system(size:30,weight:.bold)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
    }
}
struct QueuePanel: View {
    @EnvironmentObject var player: Player
    var body: some View {
        List {
            ForEach(Array(player.queue.enumerated()),id:\.element.key) { i,track in
                Button { player.playAt(i) } label: {
                    HStack {
                        Artwork(url:track.cover,size:44)
                        VStack(alignment:.leading) {
                            Text(track.title).foregroundStyle(i == player.index ? Color.accentColor : Color.primary).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if i == player.index { Image(systemName:"waveform") }
                    }
                }.buttonStyle(.plain).listRowBackground(Color.clear)
            }.onDelete(perform:player.delete)
        }.listStyle(.plain).scrollContentBackground(.hidden)
    }
}
struct CommentsPanel: View {
    @EnvironmentObject var player: Player
    @State private var items: [SongComment] = []
    @State private var note = ""
    @State private var loading = false
    @State private var page = 1
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:18) {
                ForEach(items) { item in
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(item.author).font(.caption.bold()); Spacer(); Label("\(item.likes)",systemImage:"hand.thumbsup").font(.caption).foregroundStyle(.secondary) }
                        Text(item.text).font(.body)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Divider()
                }
                if loading { ProgressView().frame(maxWidth:.infinity) }
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if !loading && !items.isEmpty { Button("更多评论") { Task { await load(reset:false) } } }
            }.padding(10)
        }.task(id:player.current?.key) { await load(reset:true) }
    }
    private func load(reset:Bool) async {
        if reset { items = []; page = 1; note = "" }
        guard let track = player.current else { return }
        let requested = reset ? 1 : page+1
        loading = true; defer { if !Task.isCancelled { loading = false } }
        do {
            let result = try await Catalog.comments(track,page:requested)
            guard !Task.isCancelled, player.current?.key == track.key else { return }
            var seen = Set<String>(); items = (items+result).filter { seen.insert($0.id).inserted }; page = requested
            if result.isEmpty { note = "暂无更多评论" }
        } catch { if !Task.isCancelled { note = error.localizedDescription } }
    }
}
