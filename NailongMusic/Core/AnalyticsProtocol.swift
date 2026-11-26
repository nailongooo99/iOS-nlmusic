import Foundation

struct AnalyticsPayload: Codable, Equatable, Sendable {
    let installation: String
    let session: String
    let visit: String
    let page: String
    let elapsed: Int
    let closed: Bool
    let model: String
    let brand: String
    let soc: String
    let soc_vendor: String
    let os: String
    let sdk: Int
    let app: String
}

enum AnalyticsProtocol {
    static let endpoint = "https://www.nailong.link/nlmusic/nailong-analytics/public/api.php?action=ingest"
    static let pages:Set<String> = ["home","playlists","mine","settings","search","player","collection","stats","backup","storage","about","privacy","network","license","disclaimer","detail"]
    static let heartbeatSeconds = 30
    static let queueCapacity = 32
    static func page(_ raw:String) -> String { pages.contains(raw) ? raw : "detail" }
    static func payload(installation:String,session:String,visit:String,page:String,elapsed:Int,closed:Bool,model:String,brand:String,soc:String,vendor:String,os:String,sdk:Int,app:String) -> AnalyticsPayload {
        .init(installation:installation,session:session,visit:visit,page:self.page(page),
              elapsed:max(0,min(86400,elapsed)),closed:closed,
              model:String(model.prefix(80)),brand:String(brand.prefix(60)),
              soc:String(soc.prefix(80)),soc_vendor:String(vendor.prefix(60)),
              os:String(os.prefix(30)),sdk:sdk,app:app)
    }
}
