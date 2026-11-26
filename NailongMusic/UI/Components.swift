import SwiftUI
import UniformTypeIdentifiers

extension View {
    @ViewBuilder func nativeGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            self.background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
        }
    }
}
struct Artwork: View {
    var url: String
    var size: CGFloat = 52
    var corner: CGFloat = 10
    var body: some View {
        AsyncImage(url:URL(string:url)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { ZStack {
                LinearGradient(colors:[Color(red:0.11,green:0.37,blue:0.37),Color(red:0.29,green:0.56,blue:0.49)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Image(systemName:"music.note").font(.system(size:size*0.34,weight:.medium)).foregroundStyle(.white.opacity(0.85))
            } }
        }
        .frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:corner))
        .accessibilityHidden(true)
    }
}
struct EmptyMessage: View {
    var title: String
    var detail: String
    var symbol: String = "music.note.list"
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:36)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth:.infinity)
    }
}
struct PlatformPicker: View {
    @Binding var platform: Platform
    var body: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                ForEach(Platform.online) { p in
                    Button { platform = p } label: {
                        Text(p.title).font(.subheadline.weight(.semibold)).padding(.horizontal,14).padding(.vertical,10)
                            .background(platform == p ? Color.accentColor : Color.secondary.opacity(0.12),in:Capsule())
                            .foregroundStyle(platform == p ? Color.white : Color.primary)
                    }.buttonStyle(.plain).accessibilityAddTraits(platform == p ? .isSelected : [])
                }
            }.padding(.horizontal,16)
        }
    }
}
struct TrackRow: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: Library
    let track: Track
    var context: [Track] = []
    var body: some View {
        HStack(spacing:11) {
            Button { player.play(track,in:context.isEmpty ? [track] : context) } label: {
                HStack(spacing:11) {
                    Artwork(url:track.cover)
                    VStack(alignment:.leading,spacing:4) {
                        Text(track.title).font(.body.weight(.medium)).foregroundStyle(player.current?.key == track.key ? Color.accentColor : Color.primary).lineLimit(1)
                        Text("\(track.artist.nonEmpty ?? "未知歌手") · \(track.platform.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength:0)
                    if player.current?.key == track.key && player.playing { Image(systemName:"waveform").foregroundStyle(Color.accentColor) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button { library.toggle(track) } label: { Label(library.isFavorite(track) ? "取消收藏" : "收藏歌曲",systemImage:library.isFavorite(track) ? "heart.slash" : "heart") }
                Button { player.addNext(track) } label: { Label("下一首播放",systemImage:"text.line.first.and.arrowtriangle.forward") }
                Button { player.enqueue(track) } label: { Label("添加到队列",systemImage:"text.append") }
                if let lists = library.data.localPlaylists,!lists.isEmpty {
                    Menu("添加到歌单") {
                        ForEach(lists) { list in Button(list.collection.name) { library.add(track,to:list.id) } }
                    }
                }
            } label: { Image(systemName:"ellipsis").font(.title3).frame(width:40,height:44).contentShape(Rectangle()) }
            .accessibilityLabel("歌曲操作")
        }
    }
}
struct CollectionRow: View {
    let collection: MusicCollection
    var body: some View {
        NavigationLink { CollectionScreen(collection:collection) } label: {
            HStack(spacing:12) {
                Artwork(url:collection.cover,size:66)
                VStack(alignment:.leading,spacing:5) {
                    Text(collection.name).font(.headline).lineLimit(2)
                    Text(collection.subtitle.nonEmpty ?? collection.platform.title).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw MusicError.message("无效文件") }
        data = bytes
    }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct MiniPlayer: View {
    @EnvironmentObject var player: Player
    var compact = false
    let open: () -> Void
    var body: some View {
        if let track = player.current {
            VStack(spacing:5) {
                HStack(spacing:11) {
                    Button(action:open) {
                        HStack(spacing:10) {
                            Artwork(url:track.cover,size:compact ? 31 : 43,corner:compact ? 6 : 8)
                            VStack(alignment:.leading,spacing:3) {
                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                if !compact { Text(player.loading ? "正在连接音源…" : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer(minLength:0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { player.toggle() } label: {
                        if player.loading { ProgressView().frame(width:44,height:44) }
                        else { Image(systemName:player.playing ? "pause.fill" : "play.fill").font(.system(size:compact ? 18 : 22)).frame(width:44,height:44) }
                    }.accessibilityLabel(player.playing ? "暂停" : "播放")
                    if !compact { Button { player.next() } label: { Image(systemName:"forward.end.fill").font(.title2).frame(width:36,height:44) }.accessibilityLabel("下一首") }
                }
                if !compact && player.duration > 0 {
                    ProgressView(value:min(1,max(0,player.position/player.duration)))
                        .progressViewStyle(.linear)
                        .accessibilityLabel("播放进度")
                }
            }.padding(.horizontal,compact ? 8 : 12).padding(.vertical,compact ? 0 : 4)
            .gesture(DragGesture(minimumDistance:25).onEnded { value in
                if value.translation.height < -35 { open() }
                else if value.translation.width < -65 { player.next() }
                else if value.translation.width > 65 { player.previous() }
            })
        }
    }
}
