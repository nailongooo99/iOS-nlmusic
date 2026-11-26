import Foundation
import CryptoKit

typealias JSON = [String: Any]
private extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSON { self[key] as? JSON ?? [:] }
    func rows(_ key: String) -> [JSON] { self[key] as? [JSON] ?? [] }
    func text(_ keys: String...) -> String {
        for key in keys {
            if let value = self[key] as? String, !value.isEmpty, value != "null" { return value }
            if let value = self[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }
    func number(_ keys: String...) -> Int64 {
        for key in keys {
            if let value = self[key] as? NSNumber { return value.int64Value }
            if let value = self[key] as? String, let n = Int64(value) { return n }
        }
        return 0
    }
    func names(_ keys: String...) -> String {
        for key in keys {
            let joined = rows(key).map { $0.text("name", "singerName", "author_name", "artistName") }.filter { !$0.isEmpty }.joined(separator: "、")
            if !joined.isEmpty { return joined }
            if let value = self[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }
}
extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
struct CatalogPage<T> {
    var items: [T]
    var more: Bool
    var note: String = ""
}
struct SongComment: Identifiable {
    let id: String
    let author: String
    let text: String
    let likes: Int64
}
enum WebClient {
    static func url(_ base: String, _ query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(string: base), components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil else { throw MusicError.message("只支持有效 HTTPS 服务地址") }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw MusicError.message("地址无效") }
        return url
    }
    static func data(_ url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], maxBytes: Int = 4 * 1024 * 1024) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.httpMethod = method; request.httpBody = body
        request.setValue("NailongMusic-iOS/1.0", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicError.message("服务器返回 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard http.url?.scheme == "https" else { throw MusicError.message("已拒绝非 HTTPS 重定向") }
        var result = Data()
        if http.expectedContentLength > Int64(maxBytes) { throw MusicError.message("响应超出大小限制") }
        for try await byte in bytes {
            result.append(byte)
            if result.count > maxBytes { throw MusicError.message("响应超出大小限制") }
        }
        return result
    }
    static func json(_ base: String, _ query: [String: String] = [:], method: String = "GET", payload: JSON? = nil, headers: [String: String] = [:]) async throws -> JSON {
        var h = headers
        var body: Data?
        if let payload { body = try JSONSerialization.data(withJSONObject: payload); h["Content-Type"] = "application/json" }
        let data = try await self.data(url(base, query), method: method, body: body, headers: h)
        guard let result = try JSONSerialization.jsonObject(with: data) as? JSON else { throw MusicError.message("平台响应不是 JSON 对象") }
        return result
    }
    static func text(_ base: String) async throws -> String {
        let bytes = try await data(url(base), maxBytes: 1024 * 1024)
        guard let value = String(data: bytes, encoding: .utf8) else { throw MusicError.message("文档不是 UTF-8") }
        return value
    }
}
enum Catalog {
    static let size = 30
    static func cover(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "{size}", with: "400")
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") { return "https://" + value.dropFirst(7) }
        return value.hasPrefix("https://") ? value : ""
    }
    static func tracks(_ rows: [JSON], _ p: Platform) -> [Track] { rows.compactMap { track($0, p) }.uniqueTracks() }
    static func track(_ r: JSON, _ p: Platform) -> Track? {
        var id = "", title = "", artist = "", art = "", duration: Int64 = 0, extra = JSON()
        switch p {
        case .wy:
            let album = r.object("al").isEmpty ? r.object("album") : r.object("al")
            id = r.text("id"); title = r.text("name"); artist = r.names("ar","artists")
            art = album.text("picUrl"); duration = r.number("dt","duration")
            extra = ["songmid": id, "albumId": album.text("id"), "albumName": album.text("name")]
        case .tx:
            let album = r.object("album"), file = r.object("file")
            id = r.text("mid","songmid","songMid").nonEmpty ?? r.text("id","songid")
            title = r.text("title","name","songname"); artist = r.names("singer")
            let albumMid = album.text("mid","albummid").nonEmpty ?? r.text("albummid")
            if !albumMid.isEmpty { art = "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(albumMid).jpg" }
            duration = min(86400,max(0,r.number("interval"))) * 1000
            extra = ["songmid":id,"songId":r.text("id","songid"),"strMediaMid":file.text("media_mid"),"albumMid":albumMid,"albumName":album.text("name","title")]
        case .kg:
            let audio = r.object("audio_info"), album = r.object("album_info")
            let hash = r.text("hash","FileHash").nonEmpty ?? audio.text("hash")
            id = r.text("audio_id","Audioid","audioid","id").nonEmpty ?? audio.text("audio_id").nonEmpty ?? hash
            let filename = r.text("filename","FileName")
            title = r.text("songname","OriSongName","SongName","ori_audio_name").nonEmpty ?? audio.text("name").nonEmpty ?? filename.components(separatedBy: " - ").last ?? ""
            artist = r.names("authors","author_name","SingerName","singername","singer").nonEmpty ?? (filename.contains(" - ") ? filename.components(separatedBy: " - ")[0] : "")
            duration = min(86400,max(0,r.number("duration"))) * 1000
            if duration == 0 { duration = audio.number("timelength") }
            art = r.text("imgurl","Image","image","album_img","cover").nonEmpty ?? album.text("imgurl","image","album_pic")
            extra = ["songmid":id,"hash":hash,"albumId":r.text("album_id").nonEmpty ?? album.text("album_id"),"albumName":album.text("album_name")]
        case .kw:
            id = r.text("MUSICRID","musicrid","id","rid").replacingOccurrences(of: "MUSIC_", with: "")
            title = r.text("SONGNAME","name","songname"); artist = r.names("ARTIST","artist","singer","artists")
            duration = min(86400,max(0,r.number("DURATION","duration"))) * 1000
            art = r.text("albumPic","pic","img","albumpic","web_albumpic_short")
            extra = ["songmid":id,"albumId":r.text("ALBUMID","albumId"),"albumName":r.text("ALBUM","album")]
        case .mg:
            id = r.text("songId","id"); title = r.text("songName","name"); artist = r.names("singerList","artists","singer")
            art = r.text("img3","img2","img1").nonEmpty ?? r.rows("albumImgs").first?.text("img") ?? ""
            if art.hasPrefix("/") && !art.hasPrefix("//") { art = "https://d.musicapp.migu.cn" + art }
            duration = min(86400,max(0,r.number("duration"))) * 1000
            extra = ["songmid":id,"copyrightId":r.text("copyrightId"),"albumName":r.text("album"),"albumId":r.text("albumId"),"lrcUrl":r.text("lrcUrl"),"mrcUrl":r.text("mrcUrl"),"trcUrl":r.text("trcUrl")]
        case .local: return nil
        }
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let encoded = (try? JSONSerialization.data(withJSONObject: extra)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Track(id: id, title: title, artist: artist, platform: p, cover: cover(art), duration: min(86400000,max(0,duration)), extra: encoded)
    }
    static func miguHeaders(_ keyword: String) -> [String:String] {
        let now = String(Int64(Date().timeIntervalSince1970 * 1000))
        let device = "963B7AA0D21511ED807EE5846EC87D20"
        let plain = "\(keyword)6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50\(device)\(now)"
        let sign = Insecure.MD5.hash(data: Data(plain.utf8)).map { String(format: "%02x", $0) }.joined()
        return ["uiVersion":"A_music_3.6.1","deviceId":device,"timestamp":now,"sign":sign,"channel":"0146921"]
    }
    static func search(_ p: Platform, _ q: String, page: Int = 1) async throws -> CatalogPage<Track> {
        let r: JSON, rows: [JSON]
        switch p {
        case .wy:
            r = try await WebClient.json("https://music.163.com/api/search/get", ["s":q,"type":"1","offset":String((page-1)*size),"limit":String(size)], headers: ["Referer":"https://music.163.com/"])
            rows = r.object("result").rows("songs")
        case .tx:
            let payload: JSON = ["comm":["ct":24,"cv":0], "req":["module":"music.search.SearchCgiService","method":"DoSearchForQQMusicDesktop","param":["query":q,"page_num":page,"num_per_page":size,"search_type":0,"grp":1]]]
            r = try await WebClient.json("https://u.y.qq.com/cgi-bin/musicu.fcg", method:"POST", payload:payload, headers:["Referer":"https://y.qq.com/"])
            rows = r.object("req").object("data").object("body").object("song").rows("list")
        case .kg:
            r = try await WebClient.json("https://songsearch.kugou.com/song_search_v2", ["keyword":q,"page":String(page),"pagesize":String(size),"userid":"0","platform":"WebFilter","filter":"2","iscorrection":"1","privilege_filter":"0","area_code":"1"])
            rows = r.object("data").rows("lists")
        case .kw:
            r = try await WebClient.json("https://search.kuwo.cn/r.s", ["client":"kt","all":q,"pn":String(page-1),"rn":String(size),"ft":"music","rformat":"json","encoding":"utf8","mobi":"1","issubtitle":"1"])
            rows = r.rows("abslist")
        case .mg:
            r = try await WebClient.json("https://jadeite.migu.cn/music_search/v3/search/searchAll", ["isCorrect":"0","isCopyright":"1","searchSwitch":#"{"song":1,"album":0,"singer":0,"songlist":0}"#,"pageSize":String(size),"text":q,"pageNo":String(page),"sort":"0","sid":"USS"], headers:miguHeaders(q))
            let matrix = r.object("songResultData")["resultList"] as? [Any] ?? []
            rows = matrix.flatMap { ($0 as? [JSON]) ?? ($0 as? JSON).map { [$0] } ?? [] }
        case .local: return .init(items:[],more:false)
        }
        let result = tracks(rows,p)
        return .init(items:result,more:rows.count >= size,note:result.isEmpty ? "没有返回可解析的歌曲；接口可能无结果或已变更。" : "")
    }
    static func daily() async throws -> [Track] {
        let r = try await WebClient.json("https://music.163.com/api/personalized/newsong", ["limit":"30"])
        let rows = r.object("data").rows("dailySongs") + r.rows("recommend") + r.rows("result").map { $0.object("song").isEmpty ? $0 : $0.object("song") }
        let list = tracks(rows,.wy)
        if list.isEmpty { throw MusicError.message("网易云未返回公开新歌") }
        return list
    }
    static func baseline(_ p: Platform) -> [MusicCollection] {
        let ids: [(String,String)]
        switch p {
        case .wy: ids = [("19723756","飙升榜"),("3779629","新歌榜"),("2884035","原创榜"),("3778678","热歌榜"),("991319590","说唱榜"),("71384707","古典榜")]
        case .tx: ids = [("4","流行指数榜"),("26","热歌榜"),("27","新歌榜"),("62","飙升榜"),("58","说唱榜"),("5","内地榜")]
        case .kg: ids = [("8888","TOP500"),("6666","飙升榜"),("59703","蜂鸟流行音乐榜"),("52144","抖音热歌榜")]
        case .kw: ids = [("93","飙升榜"),("17","新歌榜"),("16","热歌榜"),("158","抖音热歌榜")]
        case .mg: ids = [("27553319","新歌榜"),("27186466","热歌榜"),("27553408","原创榜"),("75959118","音乐风向榜")]
        case .local: ids = []
        }
        return ids.map { MusicCollection(id:$0.0,name:$0.1,platform:p,kind:"BOARD") }
    }
    static func collection(_ row: JSON, _ p: Platform, kind: String = "PLAYLIST") -> MusicCollection? {
        let basic = row.object("basic")
        let id = row.text("dissid","id","specialid","playlistid","resId","playlistId","rankid","sourceid","columnId","topId").nonEmpty ?? basic.text("tid","id","dissid")
        let title = row.text("dissname","specialname","title","name","txt","playlistName","rankname","topTitle","columnTitle","title_h5").nonEmpty ?? basic.text("title","name")
        guard !id.isEmpty, !title.isEmpty else { return nil }
        return MusicCollection(id:id,name:title,platform:p,kind:kind,
            cover:cover(row.text("imgurl","coverImgUrl","picUrl","imgUrl","pic","img","cover","img3","imageUrl","frontPicUrl").nonEmpty ?? basic.object("cover").text("medium_url","default_url")),
            subtitle:row.text("nickname","creator","userName","username","nickName","txt2").nonEmpty ?? row.object("creator").text("nickname","name"))
    }
    static func charts(_ p: Platform) async -> CatalogPage<MusicCollection> {
        do {
            let rows: [JSON]
            switch p {
            case .wy: rows = try await WebClient.json("https://music.163.com/api/toplist/detail").rows("list")
            case .tx: rows = try await WebClient.json("https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg",["format":"json","platform":"h5"]).object("data").rows("topList")
            case .kg: rows = try await WebClient.json("https://m.kugou.com/rank/list",["json":"true"]).object("rank").rows("list")
            case .kw: rows = try await WebClient.json("https://qukudata.kuwo.cn/q.k",["op":"query","cont":"tree","node":"2","pn":"0","rn":"1000","fmt":"json","level":"2"]).rows("child").flatMap { $0.rows("child") }
            case .mg: rows = try await WebClient.json("https://app.c.nf.migu.cn/pc/bmw/rank/rank-index/v1.0").object("data").rows("contents")
            case .local: rows = []
            }
            let live = rows.compactMap { collection($0,p,kind:"BOARD") }
            var seen = Set<String>()
            return .init(items:(live + baseline(p)).filter { seen.insert($0.key).inserted },more:false,note:live.isEmpty ? "显示内置榜单索引，在线详情仍需联网。" : "")
        } catch { return .init(items:baseline(p),more:false,note:"在线榜单暂不可用，显示内置索引。") }
    }
    static func playlists(_ p: Platform, query: String? = nil, page: Int = 1, sort: String = "hot") async throws -> CatalogPage<MusicCollection> {
        let rows: [JSON]
        if let q = query {
            switch p {
            case .wy: rows = try await WebClient.json("https://music.163.com/api/search/get", ["s":q,"type":"1000","offset":String((page-1)*size),"limit":String(size)]).object("result").rows("playlists")
            case .tx: rows = try await WebClient.json("https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist",["page_no":String(page-1),"num_per_page":String(size),"format":"json","query":q]).object("data").rows("list")
            case .kg: rows = try await WebClient.json("https://msearchretry.kugou.com/api/v3/search/special",["keyword":q,"page":String(page),"pagesize":String(size),"showtype":"10","filter":"0","version":"7910","sver":"2"]).object("data").rows("info")
            case .kw: rows = try await WebClient.json("https://search.kuwo.cn/r.s",["all":q,"pn":String(page-1),"rn":String(size),"rformat":"json","encoding":"utf8","ft":"playlist"]).rows("abslist")
            case .mg:
                let response = try await WebClient.json("https://jadeite.migu.cn/music_search/v3/search/searchAll",["isCorrect":"1","isCopyright":"1","searchSwitch":#"{"song":0,"album":0,"singer":0,"songlist":1}"#,"pageSize":String(size),"text":q,"pageNo":String(page),"sid":"USS"],headers:miguHeaders(q))
                let matrix = response.object("songListResultData")["result"] as? [Any] ?? []
                rows = matrix.flatMap { ($0 as? [JSON]) ?? ($0 as? JSON).map { [$0] } ?? [] }
            case .local: rows = []
            }
        } else {
            switch p {
            case .wy: rows = try await WebClient.json("https://music.163.com/api/playlist/list",["cat":"全部","order":sort,"offset":String((page-1)*size),"limit":String(size)]).rows("playlists")
            case .tx:
                let data: JSON = ["comm":["cv":1602,"ct":20],"playlist":["module":"playlist.PlayListCategoryServer","method":"get_category_content","param":["titleid":sort == "new" ? 2 : 3,"caller":"0","category_id":sort == "new" ? 2 : 3,"size":size,"page":page-1,"use_page":1]]]
                rows = try await WebClient.json("https://u.y.qq.com/cgi-bin/musicu.fcg",method:"POST",payload:data).object("playlist").object("data").object("content").rows("v_item")
            case .kg:
                let result = try await WebClient.json("https://m.kugou.com/plist/index",["json":"true","page":String(page),"pagesize":String(size)])
                rows = result.object("plist").object("list").rows("info")
            case .kw: rows = try await WebClient.json("https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList",["loginUid":"0","loginSid":"0","appUid":"76039576","pn":String(page),"rn":String(size),"order":sort == "new" ? "new" : "hot"]).object("data").rows("data")
            case .mg: let top = try await WebClient.json("https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0",["templateVersion":"2","pageNo":String(page)]).object("data").rows("contents")
                func walk(_ values: [JSON]) -> [JSON] { values.flatMap { row in (row.text("resType") == "2021" ? [row] : []) + walk(row.rows("contents")) } }
                rows = walk(top)
            case .local: rows = []
            }
        }
        var seen = Set<String>()
        let items = rows.compactMap { collection($0,p) }.filter { seen.insert($0.key).inserted }
        return .init(items:items,more:rows.count >= size,note:items.isEmpty ? "平台未返回可解析的公开歌单。" : "")
    }
    static func detail(_ c: MusicCollection, page: Int = 1) async throws -> CatalogPage<Track> {
        let rows: [JSON]
        let limit = 100
        switch c.platform {
        case .wy:
            let r = try await WebClient.json("https://music.163.com/api/playlist/detail",["id":c.id],headers:["Referer":"https://music.163.com/"])
            let all = r.object("playlist").rows("tracks").isEmpty ? r.object("result").rows("tracks") : r.object("playlist").rows("tracks")
            rows = Array(all.dropFirst(min(all.count,(page-1)*limit)).prefix(limit))
        case .tx:
            if c.kind == "BOARD" {
                let payload: JSON = ["req_1":["module":"musicToplist.ToplistInfoServer","method":"GetDetail","param":["topid":Int(c.id) ?? 0,"offset":(page-1)*limit,"num":limit]]]
                rows = try await WebClient.json("https://u.y.qq.com/cgi-bin/musicu.fcg",method:"POST",payload:payload).object("req_1").object("data").rows("songInfoList")
            } else {
                let r = try await WebClient.json("https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg",["type":"1","json":"1","utf8":"1","onlysong":"0","disstid":c.id,"format":"json"],headers:["Referer":"https://y.qq.com/"])
                let all = r.rows("cdlist").first?.rows("songlist") ?? []
                rows = Array(all.dropFirst(min(all.count,(page-1)*limit)).prefix(limit))
            }
        case .kg:
            if c.kind == "BOARD" { rows = try await WebClient.json("https://m.kugou.com/rank/info/",["rankid":c.id,"page":String(page),"json":"true"]).object("songs").rows("list") }
            else { rows = try await WebClient.json("https://mobiles.kugou.com/api/v3/special/song",["specialid":c.id,"page":String(page),"pagesize":String(limit),"version":"9108"]).object("data").rows("info") }
        case .kw:
            if c.kind == "BOARD" {
                rows = try await WebClient.json("https://kbangserver.kuwo.cn/ksong.s",["from":"pc","fmt":"json","pn":String(page-1),"rn":String(limit),"type":"bang","data":c.id]).rows("musiclist")
            } else {
                rows = try await WebClient.json("https://nplserver.kuwo.cn/pl.svc",["op":"getlistinfo","pid":c.id,"pn":String(page-1),"rn":String(limit),"encode":"utf8","keyset":"pl2012","identity":"kuwo","newver":"1"]).rows("musiclist")
            }
        case .mg:
            let base = c.kind == "BOARD" ? "https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do" : "https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0"
            let query = [c.kind == "BOARD" ? "columnId" : "playlistId":c.id,"pageNo":String(page),"pageSize":String(limit)]
            let r = try await WebClient.json(base,query,headers:["channel":"0146921"])
            rows = r.rows("songList") + r.object("data").rows("songs") + r.object("data").rows("songList") + r.rows("contentList")
        case .local: rows = []
        }
        let items = tracks(rows,c.platform)
        if items.isEmpty && page == 1 { throw MusicError.message("歌单没有返回可解析歌曲，可能是私有歌单、接口变更或链接无效。") }
        return .init(items:items,more:rows.count >= limit)
    }
    static func importCollection(_ input: String, fallback: Platform) throws -> MusicCollection {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^\d{1,30}$"#, options: .regularExpression) != nil, fallback != .local {
            return .init(id:value,name:"导入歌单 \(value)",platform:fallback)
        }
        let regex = try NSRegularExpression(pattern: #"https?://[^\s<>\"，。]+"#)
        guard let range = regex.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)).flatMap({ Range($0.range,in:value) }),
              let url = URL(string:String(value[range])), let host = url.host?.lowercased(), url.user == nil else {
            throw MusicError.message("请输入平台公开歌单完整链接或数字 ID")
        }
        let domains: [(String,Platform)] = [("music.163.com",.wy),("y.qq.com",.tx),("qq.com",.tx),("kugou.com",.kg),("kuwo.cn",.kw),("migu.cn",.mg)]
        guard let platform = domains.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) })?.1 else { throw MusicError.message("不支持该歌单域名") }
        let combined = url.absoluteString
        let pattern = #"(?:[?&#](?:id|disstid|dissid|pid|playlistId|playlistid|specialid)=|/(?:playlist|playlist_detail|playsquare|single)/)(\d{1,30})(?!\d)"#
        let match = try NSRegularExpression(pattern:pattern,options:.caseInsensitive).firstMatch(in:combined,range:NSRange(combined.startIndex...,in:combined))
        guard let idRange = match.flatMap({ Range($0.range(at:1),in:combined) }) else { throw MusicError.message("无法识别歌单 ID，请复制公开详情页完整链接（短链暂不解析）") }
        let id = String(combined[idRange])
        return .init(id:id,name:"导入歌单 \(id)",platform:platform)
    }
    static func lyrics(_ track: Track, service: String) async throws -> [LyricLine] {
        let id = track.id
        if track.platform == .wy {
            do {
                let r = try await WebClient.json("https://music.163.com/api/song/lyric",["id":id,"lv":"-1","tv":"-1","yv":"-1"],headers:["Referer":"https://music.163.com/"])
                let trans = r.object("tlyric").text("lyric")
                let lines = Lyrics.complete(Lyrics.parse(r.object("yrc").text("lyric"),translation:trans),base:Lyrics.parse(r.object("lrc").text("lyric"),translation:trans))
                if !lines.isEmpty { return lines }
            } catch { if Task.isCancelled { throw CancellationError() } }
            if !service.isEmpty {
                let root = try await WebClient.json(service + "ncm/lyric",["id":id])
                let r = root.object("data").isEmpty ? root : root.object("data")
                let lines = Lyrics.parse(r.object("yrc").text("lyric").nonEmpty ?? r.object("lrc").text("lyric"),translation:r.object("tlyric").text("lyric"))
                if !lines.isEmpty { return lines }
            }
        } else if track.platform == .tx {
            let r = try await WebClient.json("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",["songmid":track.metadata["songmid"] ?? id,"format":"json","nobase64":"1"],headers:["Referer":"https://y.qq.com/"])
            func decoded(_ value: String) -> String { Data(base64Encoded:value).flatMap { String(data:$0,encoding:.utf8) } ?? value }
            return Lyrics.parse(decoded(r.text("lyric")),translation:decoded(r.text("trans")))
        } else if track.platform == .kg {
            let hash = track.metadata["hash"]?.nonEmpty ?? id
            let found = try await WebClient.json("https://lyrics.kugou.com/search",["ver":"1","man":"yes","client":"pc","keyword":track.title,"hash":hash,"timelength":String(track.duration),"lrctxt":"1"])
            guard let candidate = found.rows("candidates").first else { throw MusicError.message("酷狗未返回歌词候选") }
            let result = try await WebClient.json("https://lyrics.kugou.com/download",["ver":"1","client":"pc","id":candidate.text("id"),"accesskey":candidate.text("accesskey"),"fmt":"lrc","charset":"utf8"])
            guard let data = Data(base64Encoded:result.text("content"),options:.ignoreUnknownCharacters),let text = String(data:data,encoding:.utf8) else { throw MusicError.message("酷狗普通歌词无法解码") }
            return Lyrics.parse(text)
        } else if track.platform == .kw {
            let root = try await WebClient.json("https://www.kuwo.cn/openapi/v1/www/lyric/getlyric",["musicId":id,"httpsStatus":"1"],headers:["Referer":"https://www.kuwo.cn/"])
            return root.object("data").rows("lrclist").compactMap { row in
                let text = row.text("lineLyric")
                guard let time = Double(row.text("time")),time.isFinite,time >= 0,!text.isEmpty else { return nil }
                return LyricLine(time:time,text:text)
            }.sorted { $0.time < $1.time }
        } else if track.platform == .mg, let raw = track.metadata["lrcUrl"], !raw.isEmpty {
            let trans: String
            if let translation = track.metadata["trcUrl"], !translation.isEmpty { trans = (try? await WebClient.text(cover(translation))) ?? "" }
            else { trans = "" }
            return Lyrics.parse(try await WebClient.text(cover(raw)),translation:trans)
        }
        throw MusicError.message("当前平台未返回受支持的歌词；可导入本地 LRC/YRC 文件。")
    }

    static func comments(_ track: Track, page: Int = 1) async throws -> [SongComment] {
        let r: JSON, rows: [JSON]
        let limit = 20
        switch track.platform {
        case .wy:
            r = try await WebClient.json("https://music.163.com/api/v1/resource/comments/R_SO_4_\(track.id)",["limit":"20","offset":String((page-1)*20)],headers:["Referer":"https://music.163.com/"])
            rows = r.rows("comments")
        case .tx:
            let id = track.metadata["songId"]?.nonEmpty ?? track.id
            let payload: JSON = ["req":["module":"music.globalComment.CommentRead","method":"GetHotCommentList","param":["BizType":1,"BizId":id,"LastCommentSeqNo":"","PageSize":limit,"PageNum":page-1,"HotType":1,"WithAirborne":0,"PicEnable":1]]]
            r = try await WebClient.json("https://u.y.qq.com/cgi-bin/musicu.fcg",method:"POST",payload:payload,headers:["Referer":"https://y.qq.com/"])
            rows = r.object("req").object("data").object("CommentList").rows("Comments")
        case .kg:
            let hash = track.metadata["hash"]?.nonEmpty ?? track.id
            let params: [String:String] = ["dfid":"0","mid":"16249512204336365674023395779019","clienttime":String(Int64(Date().timeIntervalSince1970*1000)),"uuid":"0","extdata":hash,"appid":"1005","code":"fc4be23b4e972707f36b8a828a93ba8a","schash":hash,"clientver":"11409","p":String(page),"clienttoken":"","pagesize":String(limit),"ver":"10","kugouid":"0"]
            let secret = "OIlwieks28dk2k092lksi2UIkp"
            let raw = params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined()
            let signature = Insecure.MD5.hash(data:Data((secret+raw+secret).utf8)).map { String(format:"%02x",$0) }.joined()
            r = try await WebClient.json("https://m.comment.service.kugou.com/r/v1/rank/topliked",params.merging(["signature":signature]) { _,new in new })
            rows = r.rows("list")
        case .kw:
            r = try await WebClient.json("https://ncomment.kuwo.cn/com.s",["f":"web","type":"get_rec_comment","aapiver":"1","prod":"kwplayer_ar_10.5.2.0","digest":"15","sid":track.id,"start":String((page-1)*limit),"msgflag":"1","count":"20","newver":"3","uid":"0"],headers:["Referer":"https://www.kuwo.cn/"])
            rows = r.rows("hot_comments")
        case .mg:
            r = try await WebClient.json("https://app.c.nf.migu.cn/MIGUM3.0/user/comment/stack/v1.0",["pageSize":String(limit),"queryType":"2","resourceId":track.id,"resourceType":"2","hotCommentStart":String((page-1)*limit)],headers:["channel":"0146921"])
            rows = r.object("data").rows("hotComments")
        case .local: return []
        }
        return rows.compactMap { row in
            let text = row.text("content","Content","msg","commentInfo")
            guard !text.isEmpty else { return nil }
            let name = row.text("Nick","user_name","u_name").nonEmpty ?? row.object("user").text("nickname","nickName")
            let likes = max(0,max(row.number("likedCount","PraiseNum","like_num"),max(row.object("like").number("likenum"),row.object("opNumItem").number("thumbNum"))))
            return .init(id:row.text("commentId","CmId","id").nonEmpty ?? "\(name):\(text)",author:name,text:text,likes:likes)
        }
    }
}
