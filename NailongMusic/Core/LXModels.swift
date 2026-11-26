import Foundation

struct LXMetadata: Codable, Equatable, Sendable {
    var name: String
    var author: String = ""
    var version: String = ""
    var description: String = ""
    var homepage: String = ""
    static func parse(_ script: String, fallback: String) -> Self {
        var result = Self(name: String(fallback.prefix(120)))
        // Read only the first leading documentation block, never execute code for metadata.
        let prefix = String(script.prefix(16384)).trimmingCharacters(in:.whitespacesAndNewlines)
        guard prefix.hasPrefix("/*"), let end = prefix.range(of:"*/") else { return result }
        let header = prefix[..<end.lowerBound]
        let pattern = #"(?m)^\s*\*?\s*@(name|author|version|description|homepage)\s+([^\r\n]+)"#
        let regex = try! NSRegularExpression(pattern:pattern)
        let ns = String(header) as NSString
        for match in regex.matches(in:ns as String,range:NSRange(location:0,length:ns.length)) {
            let key = ns.substring(with:match.range(at:1))
            let value = String(ns.substring(with:match.range(at:2)).trimmingCharacters(in:.whitespacesAndNewlines).prefix(512))
            switch key {
            case "name": if !value.isEmpty { result.name = String(value.prefix(120)) }
            case "author": result.author = value
            case "version": result.version = value
            case "description": result.description = value
            case "homepage": result.homepage = value
            default: break
            }
        }
        return result
    }
}

struct LXSource: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var metadata: LXMetadata
    var origin: String
    var script: String
    var enabled = false
    var supported: [String:[String]] = [:]
    var status = "待初始化"
    var checkedAt: Date? = nil
    var name: String { metadata.name }
}

enum LXProtocol {
    static let qualities = ["flac24bit","flac","320k","128k"]
    static let platforms = ["wy","tx","kg","kw","mg"]
    static let maxScriptBytes = 1024 * 1024
    static func order(_ requested: String, supported: [String]) -> [String] {
        let index = qualities.firstIndex(of:requested) ?? 2
        return qualities[index...].filter { supported.contains($0) }
    }
    static func capabilities(_ raw: String) throws -> [String:[String]] {
        guard let data = raw.data(using:.utf8),
              let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              (object["status"] as? Bool) != false,
              let sources = object["sources"] as? [String:Any] else {
            throw MusicError.message("LX 音源未返回有效初始化信息")
        }
        var result: [String:[String]] = [:]
        for platform in platforms {
            guard let entry = sources[platform] as? [String:Any],
                  entry["type"] as? String == "music",
                  let actions = entry["actions"] as? [String], actions.contains("musicUrl") else { continue }
            if entry["qualitys"] != nil && !(entry["qualitys"] is [String]) { continue }
            let advertised = (entry["qualitys"] as? [String])?.map { $0.lowercased() } ?? qualities
            let valid = qualities.filter { advertised.contains($0) }
            if !valid.isEmpty { result[platform] = valid }
        }
        guard !result.isEmpty else { throw MusicError.message("音源没有声明受支持的 musicUrl 平台及音质") }
        return result
    }
    // Script and index downloads remain HTTPS-only. LX media/request transport
    // accepts signed public HTTP(S) URLs without rewriting the scheme or query.
    static func httpsURL(_ raw:String) throws -> URL {
        try publicURL(raw,allowHTTP:false,standardPortOnly:true)
    }
    static func mediaURL(_ raw:String) throws -> URL {
        try publicURL(raw,allowHTTP:true,standardPortOnly:false)
    }
    private static func publicURL(_ raw:String,allowHTTP:Bool,standardPortOnly:Bool) throws -> URL {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let allowedSchemes=allowHTTP ? ["http","https"] : ["https"]
        guard !value.isEmpty,value.utf8.count<=4096,
              value.rangeOfCharacter(from:.whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let c=URLComponents(string:value),let scheme=c.scheme?.lowercased(),allowedSchemes.contains(scheme),
              c.user==nil,c.password==nil,
              let host=c.host?.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".")),
              host.count<=253,host.contains("."),
              host.range(of:#"^[a-z0-9.-]+$"#,options:.regularExpression) != nil,
              host.split(separator:".").last?.contains(where:{$0.isLetter}) == true,
              !["localhost","local","internal","lan","home","test","invalid","onion"].contains(where:{host==$0 || host.hasSuffix("."+$0)}),
              c.port.map({ (1...65535).contains($0) && (!standardPortOnly || $0==443) }) ?? true,
              let url=URL(string:value) else {
            throw MusicError.message(allowHTTP ? "音源未返回有效公网 HTTP/HTTPS 地址" : "脚本及索引仅支持公网 HTTPS（443 端口）")
        }
        return url
    }
    static func indexURLs(_ text: String) -> [String] {
        guard !text.prefix(512).lowercased().contains("<html") else { return [] }
        let regex = try! NSRegularExpression(pattern:#"https://[^\s<>"'`)\]]+"#,options:.caseInsensitive)
        var seen = Set<String>(), result:[String] = []
        for line in text.components(separatedBy:.newlines) where !line.trimmingCharacters(in:.whitespaces).hasPrefix("#") {
            let ns = line as NSString
            for match in regex.matches(in:line,range:NSRange(location:0,length:ns.length)) {
                let raw = ns.substring(with:match.range).trimmingCharacters(in:CharacterSet(charactersIn:".,;"))
                guard raw.count <= 2048, let url = try? httpsURL(raw),
                      url.pathExtension.lowercased() == "js", seen.insert(url.absoluteString).inserted else { continue }
                result.append(url.absoluteString)
                if result.count == 512 { return result }
            }
        }
        return result
    }
    static func musicInfo(_ track: Track) -> [String:Any] {
        let raw = (try? JSONSerialization.jsonObject(with:Data(track.extra.utf8))) as? [String:Any] ?? [:]
        // Only portable metadata, never forward playback URLs, cookies, or credentials.
        let allowed = Set(["songmid","songId","strMediaMid","albumMid","albumId","albumName","hash","audioId","copyrightId","interval","_interval","types","_types","lrcUrl","mrcUrl","trcUrl","img"])
        var info = raw.filter { allowed.contains($0.key) }
        func string(_ key:String,_ fallback:String) -> String {
            if let s = info[key] as? String, !s.isEmpty { return s }
            if let n = info[key] as? NSNumber { return n.stringValue }
            return fallback
        }
        info["songmid"] = string("songmid",track.id)
        info["songId"] = string("songId",track.id)
        info["name"] = track.title; info["singer"] = track.artist; info["source"] = track.platform.rawValue
        info["img"] = track.cover; info["albumName"] = string("albumName","")
        let seconds = max(0,track.duration/1000)
        if seconds > 0 {
            if info["interval"] == nil { info["interval"] = String(format:"%02lld:%02lld",seconds/60,seconds%60) }
            if info["_interval"] == nil { info["_interval"] = seconds }
        }
        func qualityFields(_ row:[String:Any]) -> [String:Any] {
            row.filter { ["type","size","hash"].contains($0.key) && ($0.value is String || $0.value is NSNumber) }
        }
        if let list=info["types"] as? [[String:Any]] {
            info["types"]=list.filter { qualities.contains($0["type"] as? String ?? "") }.map(qualityFields)
        } else { info["types"] = [["type":"128k"]] }
        if let map=info["_types"] as? [String:[String:Any]] {
            info["_types"]=map.filter { qualities.contains($0.key) }.mapValues(qualityFields)
        } else { info["_types"] = ["128k":[:]] as [String:[String:String]] }
        info["typeUrl"] = [String:String]()
        return info
    }
}
