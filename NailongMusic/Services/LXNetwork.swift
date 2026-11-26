import Foundation
import Darwin

private final class LXNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class LXDNSResult: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Bool,Never>?
    init(_ value:CheckedContinuation<Bool,Never>) { continuation=value }
    func finish(_ value:Bool) {
        lock.lock();let current=continuation;continuation=nil;lock.unlock()
        current?.resume(returning:value)
    }
}

enum LXNetwork {
    private static let dnsSlots=DispatchSemaphore(value:4)
    struct Reply {
        let status: Int
        let headers: [String:String]
        let data: Data
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 22
        return URLSession(configuration:config,delegate:LXNoRedirect(),delegateQueue:nil)
    }()
    static func checked(_ raw:String,allowHTTP:Bool=false) async throws -> URL {
        let url = try allowHTTP ? LXProtocol.mediaURL(raw) : LXProtocol.httpsURL(raw)
        guard let host = url.host else { throw MusicError.message("缺少音源域名") }
        // Check all resolved addresses. URLSession resolves independently; this is a
        // defense-in-depth check, not DNS pinning or a hostile-code security boundary.
        let publicHost = await withCheckedContinuation { (continuation:CheckedContinuation<Bool,Never>) in
            guard Self.dnsSlots.wait(timeout:.now()) == .success else { continuation.resume(returning:false);return }
            let result=LXDNSResult(continuation)
            DispatchQueue.global(qos:.utility).async {
                defer { Self.dnsSlots.signal() }
                result.finish(Self.isPublicHost(host))
            }
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+4) { result.finish(false) }
        }
        try Task.checkCancellation()
        guard publicHost else { throw MusicError.message("音源域名无法解析，或解析到非公网地址") }
        return url
    }
    private static func isPublicHost(_ host:String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host,nil,&hints,&result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var count = 0
        while let ptr = cursor {
            let entry = ptr.pointee
            if entry.ai_family == AF_INET || entry.ai_family == AF_INET6 {
                var name = [CChar](repeating:0,count:Int(NI_MAXHOST))
                let size = socklen_t(name.count)
                guard getnameinfo(entry.ai_addr,entry.ai_addrlen,&name,size,nil,0,NI_NUMERICHOST) == 0,
                      publicAddress(String(cString:name)) else { return false }
                count += 1
            }
            cursor = entry.ai_next
        }
        return count > 0
    }
    private static func publicAddress(_ address:String) -> Bool {
        if address.contains(":") {
            var ip = in6_addr()
            guard inet_pton(AF_INET6,address,&ip) == 1 else { return false }
            return withUnsafeBytes(of:&ip) { bytes in
                // Only global unicast 2000::/3; reject documentation and tunnel ranges.
                bytes.count == 16 && (bytes[0] & 0xe0) == 0x20 &&
                !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) &&
                !(bytes[0] == 0x20 && bytes[1] == 0x02)
            }
        }
        let p = address.split(separator:".").compactMap { Int($0) }
        guard p.count == 4,p.allSatisfy({(0...255).contains($0)}) else { return false }
        let a=p[0], b=p[1], c=p[2]
        return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                 (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
                 (a == 172 && (16...31).contains(b)) || (a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) ||
                 (a == 198 && ((18...19).contains(b) || (b == 51 && c == 100))) ||
                 (a == 203 && b == 0 && c == 113))
    }
    static func load(_ raw:String, maxBytes:Int) async throws -> Data {
        let reply = try await fetch(raw,method:"GET",headers:[:],body:nil,timeout:12,maxBytes:maxBytes)
        guard (200..<300).contains(reply.status) else { throw MusicError.message("HTTP \(reply.status)") }
        return reply.data
    }
    static func fetch(_ raw:String,method:String,headers:[String:String],body:Data?,timeout:Double,maxBytes:Int,allowHTTP:Bool=false) async throws -> Reply {
        var target = raw, verb = method, payload = body, fields = headers
        for attempt in 0...4 {
            try Task.checkCancellation()
            let url = try await checked(target,allowHTTP:allowHTTP)
            var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:timeout)
            request.httpMethod = verb; request.httpBody = payload
            request.setValue("NailongMusic-iOS/1.0",forHTTPHeaderField:"User-Agent")
            for (key,value) in fields { request.setValue(value,forHTTPHeaderField:key) }
            let (bytes,response) = try await session.bytes(for:request)
            guard let http = response as? HTTPURLResponse else { throw MusicError.message("音源返回无效 HTTP 响应") }
            if [301,302,303,307,308].contains(http.statusCode) {
                guard attempt < 4, let location = http.value(forHTTPHeaderField:"Location"),
                      let next = URL(string:location,relativeTo:url)?.absoluteURL else { throw MusicError.message("音源跳转失败或次数超限") }
                _ = try allowHTTP ? LXProtocol.mediaURL(next.absoluteString) : LXProtocol.httpsURL(next.absoluteString)
                guard !(url.scheme?.lowercased()=="https" && next.scheme?.lowercased() != "https") else {
                    throw MusicError.message("拒绝 HTTPS 降级重定向")
                }
                // Never forward credentials to another origin.
                if next.host?.lowercased() != url.host?.lowercased() || next.port != url.port || next.scheme != url.scheme {
                    fields = fields.filter { !["authorization","cookie","proxy-authorization"].contains($0.key.lowercased()) }
                }
                if [301,302,303].contains(http.statusCode) && verb == "POST" {
                    verb = "GET"; payload = nil
                    fields = fields.filter { $0.key.lowercased() != "content-type" }
                }
                target = next.absoluteString
                // Drain only a bounded amount of a redirect response.
                var drained = 0
                for try await _ in bytes { drained += 1; if drained >= 4096 { break } }
                continue
            }
            guard http.expectedContentLength <= Int64(maxBytes) else { throw MusicError.message("音源响应过大") }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw MusicError.message("音源响应过大") }
            }
            var resultHeaders:[String:String] = [:]
            for (key,value) in http.allHeaderFields {
                let name = String(describing:key).lowercased()
                if name.count <= 80 && name != "set-cookie" { resultHeaders[name] = String(String(describing:value).prefix(2048)) }
            }
            return Reply(status:http.statusCode,headers:resultHeaders,data:data)
        }
        throw MusicError.message("音源跳转失败")
    }
    static func scriptRequest(_ raw:String,options:[String:Any]) async throws -> [String:Any] {
        let method = (options["method"] as? String ?? "GET").uppercased()
        guard ["GET","POST"].contains(method) else { throw MusicError.message("LX 仅支持 GET / POST 请求") }
        var headers:[String:String] = [:]
        for (key,value) in (options["headers"] as? [String:Any] ?? [:]).prefix(40) {
            guard key.range(of:#"^[A-Za-z0-9-]{1,60}$"#,options:.regularExpression) != nil,
                  !["host","connection","content-length","transfer-encoding","proxy-authorization","accept-encoding"].contains(key.lowercased()) else { continue }
            let str = String(describing:value)
            if str.count <= 2048 && !str.contains("\r") && !str.contains("\n") { headers[key] = str }
        }
        var body:Data?
        func contentType(_ value:String) {
            if !headers.keys.contains(where:{$0.lowercased() == "content-type"}) { headers["Content-Type"] = value }
        }
        if method == "POST" {
            if let form = options["formData"] as? [String:Any] {
                let boundary = "Nailong-\(UUID().uuidString)"
                var text = ""
                for (key,value) in form {
                    guard key.range(of:#"^[A-Za-z0-9_.-]{1,80}$"#,options:.regularExpression) != nil,
                          value is String || value is NSNumber else { throw MusicError.message("multipart 仅支持文本字段") }
                    text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
                }
                text += "--\(boundary)--\r\n"; body = Data(text.utf8)
                contentType("multipart/form-data; boundary=\(boundary)")
            } else if let form = options["form"] as? [String:Any] {
                let allowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
                func enc(_ value:String) -> String { (value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "").replacingOccurrences(of:"%20",with:"+") }
                let value = form.sorted{$0.key < $1.key}.map { enc($0.key)+"="+enc(String(describing:$0.value)) }.joined(separator:"&")
                body = Data(value.utf8); contentType("application/x-www-form-urlencoded")
            } else if let raw = options["body"], !(raw is NSNull) {
                if let text = raw as? String { body = Data(text.utf8) }
                else { body = try JSONSerialization.data(withJSONObject:raw,options:.fragmentsAllowed) }
                contentType("application/json")
            }
        }
        guard (body?.count ?? 0) <= 256*1024 else { throw MusicError.message("音源请求体过大") }
        let ms = (options["timeout"] as? NSNumber)?.doubleValue ?? 13000
        let seconds = ms.isFinite ? min(18,max(1,ms/1000)) : 13
        let reply = try await fetch(raw,method:method,headers:headers,body:body,timeout:seconds,maxBytes:2*1024*1024,allowHTTP:true)
        var result:[String:Any] = ["statusCode":reply.status,"statusMessage":HTTPURLResponse.localizedString(forStatusCode:reply.status),"headers":reply.headers]
        if options["binary"] as? Bool == true { result["binaryBase64"] = reply.data.base64EncodedString() }
        else if let object = try? JSONSerialization.jsonObject(with:reply.data) { result["body"] = object }
        else { result["body"] = String(decoding:reply.data,as:UTF8.self) }
        return result
    }
}
