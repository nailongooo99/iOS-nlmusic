import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryScreen: View {
    @EnvironmentObject var library: Library
    @State private var creating = false
    @State private var name = ""
    @State private var importing = false
    @State private var addingURL = false
    @State private var audioName = ""
    @State private var audioAddress = ""
    var body: some View {
        List {
            Section("我的音乐") {
                NavigationLink { TrackListScreen(title:"我喜欢的音乐",type:.favorites) } label: { Label("我喜欢的音乐",systemImage:"heart.fill") }
                NavigationLink { TrackListScreen(title:"最近播放",type:.recent) } label: { Label("最近播放",systemImage:"clock") }
                NavigationLink { StatisticsScreen() } label: { Label("听歌统计与唱片墙",systemImage:"chart.bar.xaxis") }
                Button { importing = true } label: { Label("导入本地音频",systemImage:"folder.badge.plus") }
                Button { audioName = ""; audioAddress = ""; addingURL = true } label: { Label("导入授权音频链接",systemImage:"link.badge.plus") }
            }
            Section("自建歌单") {
                ForEach(library.data.localPlaylists ?? []) { snapshot in CollectionRow(collection:snapshot.collection) }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { (library.data.localPlaylists ?? []).indices.contains($0) ? library.data.localPlaylists?[$0].id : nil }
                        ids.forEach { library.deletePlaylist($0) }
                    }
                Button { name = ""; creating = true } label: { Label("新建歌单",systemImage:"plus.circle") }
            }
            Section("收藏歌单") {
                ForEach(library.data.playlists,id:\.key) { collection in
                    CollectionRow(collection:collection).swipeActions {
                        Button(role:.destructive) { library.toggle(collection) } label: { Label("移除",systemImage:"trash") }
                    }
                }
                if library.data.playlists.isEmpty { Text("收藏的公开歌单会出现在这里").font(.caption).foregroundStyle(.secondary) }
            }
        }.scrollChrome().navigationTitle("我的")
        .alert("新建歌单",isPresented:$creating) {
            TextField("名称",text:$name)
            Button("取消",role:.cancel) {}
            Button("创建") { let n = name.trimmingCharacters(in:.whitespacesAndNewlines); if !n.isEmpty { library.create(String(n.prefix(100))) } }
        }
        .sheet(isPresented:$addingURL) {
            NavigationStack {
                Form {
                    TextField("歌曲名称（可选）",text:$audioName)
                    TextField("HTTPS 音频直链",text:$audioAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("仅导入本人拥有权利或已取得授权的音频文件地址。不接受平台会员页面或 DRM 内容。").font(.footnote).foregroundStyle(.secondary)
                    Button("添加到我的音乐") {
                        do { try library.importAuthorizedURL(name:audioName,address:audioAddress.trimmingCharacters(in:.whitespacesAndNewlines)); addingURL = false }
                        catch { library.error = error.localizedDescription; addingURL = false }
                    }.disabled(audioAddress.isEmpty)
                }.navigationTitle("授权音频").analyticsPage("detail").toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { addingURL = false } } }
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.audio],allowsMultipleSelection:true) { result in
            switch result { case .success(let urls): library.importAudio(urls); case .failure(let error): library.error = error.localizedDescription }
        }
    }
}
struct TrackListScreen: View {
    enum Kind { case favorites, recent }
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Player
    let title: String
    let type: Kind
    var tracks: [Track] { type == .favorites ? library.data.favorites : library.data.recent }
    var body: some View {
        List {
            if tracks.isEmpty { EmptyMessage(title:"还没有歌曲",detail:"在搜索结果或播放页收藏音乐。") }
            else {
                Button { if let first = tracks.first { player.play(first,in:tracks) } } label: { Label("播放全部",systemImage:"play.fill") }
                ForEach(tracks,id:\.key) { TrackRow(track:$0,context:tracks) }
            }
        }.scrollChrome().navigationTitle(title).analyticsPage("detail")
    }
}
struct StatisticsScreen: View {
    @EnvironmentObject var library: Library
    @State private var exportURL: URL?
    @State private var message = ""
    @State private var rendering = false
    var records: [ListeningRecord] { library.data.statistics ?? [] }
    var ranked: [(key:String,title:String,artist:String,millis:Int64)] {
        Dictionary(grouping:records,by:\.key).compactMap { key,group -> (key:String,title:String,artist:String,millis:Int64)? in
            guard let first = group.first else { return nil }
            return (key,first.title,first.artist,group.reduce(0){$0+$1.millis})
        }.sorted { $0.millis > $1.millis }
    }
    var wall: [Track] {
        let tracks = library.data.recent + library.data.favorites + (library.data.localPlaylists ?? []).flatMap(\.tracks)
        return ranked.prefix(9).compactMap { record in
            tracks.first(where:{$0.key == record.key}) ?? Track(id:record.key,title:record.title,artist:record.artist,platform:.local)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(spacing:16) {
                    metric("累计听歌",value:String(format:"%.1f 小时",Double(records.reduce(Int64(0)){$0+$1.millis})/3_600_000))
                    metric("播放次数",value:"\(records.reduce(0){$0+$1.plays})")
                }
                Text("最常听的歌曲").font(.title2.bold())
                if ranked.isEmpty { EmptyMessage(title:"暂无统计",detail:"完成实际播放后即可看到听歌记录。") }
                ForEach(Array(ranked.prefix(10).enumerated()),id:\.offset) { index,item in
                    VStack(alignment:.leading,spacing:5) {
                        HStack {
                            Text("\(index+1)").foregroundStyle(.secondary).monospacedDigit()
                            VStack(alignment:.leading) { Text(item.title).font(.headline); Text(item.artist).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(item.millis/60000) 分钟").font(.caption).monospacedDigit()
                        }
                        ProgressView(value:Double(item.millis),total:Double(max(1,ranked.first?.millis ?? 1))).tint(Color.accentColor)
                    }
                }
                Text("唱片墙").font(.title2.bold())
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:8) {
                    ForEach(wall,id:\.key) { track in
                        VStack(spacing:4) { Artwork(url:track.cover,size:88); Text(track.title).lineLimit(1).font(.caption2) }
                    }
                }
                HStack {
                    Button("生成海报") { Task { await render(wallpaper:false) } }
                    Button("生成壁纸") { Task { await render(wallpaper:true) } }
                }.buttonStyle(.bordered).disabled(wall.isEmpty || rendering)
                if rendering { ProgressView("生成中") }
                if let exportURL { ShareLink(item:exportURL) { Label("保存或分享 PNG",systemImage:"square.and.arrow.up") } }
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }.scrollChrome().navigationTitle("听歌统计").analyticsPage("stats")
    }
    private func metric(_ name:String,value:String) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6)
        }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
    }
    @MainActor private func render(wallpaper:Bool) async {
        rendering = true; exportURL = nil; message = ""; defer { rendering = false }
        var pictures: [UIImage?] = []
        for track in wall {
            if let url = URL(string:track.cover), url.scheme == "https",
               let bytes = try? await WebClient.data(url,maxBytes:3*1024*1024) { pictures.append(UIImage(data:bytes)) }
            else { pictures.append(nil) }
        }
        let view = Poster(tracks:wall,pictures:pictures,wallpaper:wallpaper)
        let renderer = ImageRenderer(content:view)
        renderer.scale = 2
        guard let image = renderer.uiImage,let png = image.pngData() else { message = "图片生成失败"; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(wallpaper ? "Nailong-Wallpaper.png" : "Nailong-Poster.png")
        do { try png.write(to:url,options:.atomic); exportURL = url }
        catch { message = error.localizedDescription }
    }
}
struct Poster: View {
    let tracks: [Track]
    let pictures: [UIImage?]
    let wallpaper: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Spacer(minLength:0)
            Text("NAILONG MUSIC").font(.system(size:13,weight:.bold)).tracking(5).foregroundStyle(.yellow)
            Text("我的唱片墙").font(.system(size:34,weight:.bold)).foregroundStyle(.white)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:3),spacing:10) {
                ForEach(Array(tracks.enumerated()),id:\.offset) { i,track in
                    VStack(spacing:5) {
                        ZStack {
                            RoundedRectangle(cornerRadius:9).fill(Color.white.opacity(0.13))
                            if pictures.indices.contains(i),let image = pictures[i] { Image(uiImage:image).resizable().scaledToFill() }
                            else { Image(systemName:"music.note").font(.title).foregroundStyle(.yellow) }
                        }.frame(width:102,height:102).clipped().clipShape(RoundedRectangle(cornerRadius:9))
                        Text(track.title).font(.system(size:10,weight:.semibold)).foregroundStyle(.white).lineLimit(1).frame(width:102)
                    }
                }
            }
            Text("每一首歌，都是生活的回声。").font(.caption).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength:0)
        }.padding(26).frame(width:390,height:wallpaper ? 844 : 550).background(Color(red:0.09,green:0.25,blue:0.26))
    }
}
