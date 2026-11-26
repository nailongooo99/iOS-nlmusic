import Foundation
import JavaScriptCore

// Contexts live on a single dedicated serial lane. A hostile infinite loop
// cannot be force-interrupted through public JavaScriptCore APIs. Bound the
// queue and fail closed rather than spawning new threads for timed-out scripts.
private final class LXWorker: @unchecked Sendable {
    private static let lane=DispatchQueue(label:"music.nailong.lx.js",qos:.userInitiated)
    private static let slots=DispatchSemaphore(value:16)
    private let lock=NSLock()
    private var stopped=false
    private var context:JSContext?
    private var emitted=0
    private var isStopped:Bool { lock.lock();defer{lock.unlock()};return stopped }
    func stop() { lock.lock();stopped=true;lock.unlock() }
    private func enqueue(_ operation:@escaping (LXWorker)->Void) -> Bool {
        guard !isStopped, Self.slots.wait(timeout:.now()) == .success else { return false }
        Self.lane.async { [self] in
            defer { if isStopped { context=nil };Self.slots.signal() }
            guard !isStopped else { return }
            operation(self)
        }
        return true
    }
    func start(script:String,bootstrap:String,metadata:String,emit:@escaping (String,String)->Void) -> Bool {
        enqueue { worker in
            guard let ctx=JSContext() else { emit("scriptError","无法创建 JavaScriptCore 上下文");return }
            worker.context=ctx
            ctx.exceptionHandler={ _,error in emit("scriptError",String((error?.toString() ?? "JavaScript error").prefix(250))) }
            let post:@convention(block) (String,String)->Void = { [weak worker] action,raw in
                guard let worker,!worker.isStopped,action.count<=32,raw.utf8.count<=2*1024*1024 else { return }
                worker.emitted+=1
                if worker.emitted>256 {
                    if worker.emitted==257 { emit("scriptError","音源事件数量超限") }
                    worker.stop();return
                }
                emit(action,raw)
            }
            let utility:@convention(block) (String,String)->String = { [weak worker] operation,raw in
                guard worker?.isStopped == false else { return "" }
                return LXCrypto.run(operation,raw)
            }
            ctx.setObject(post,forKeyedSubscript:"__nlPost" as NSString)
            ctx.setObject(utility,forKeyedSubscript:"__nlUtility" as NSString)
            ctx.setObject(metadata,forKeyedSubscript:"__nlMetadata" as NSString)
            ctx.evaluateScript(bootstrap)
            guard !worker.isStopped else { return }
            ctx.evaluateScript(script)
        }
    }
    func invoke(_ function:String,args:[String]) -> Bool {
        enqueue { worker in
            worker.context?.objectForKeyedSubscript(function)?.call(withArguments:args)
        }
    }
}

@MainActor final class LXRuntime {
    private let worker=LXWorker()
    private let bootstrapOverride:String?
    init(bootstrapOverride:String?=nil) { self.bootstrapOverride=bootstrapOverride }
    private var pending:CheckedContinuation<String,Error>?
    private var pendingKey:String?
    private var timer:Task<Void,Never>?
    private var http:[String:Task<Void,Never>]=[:]
    private var jsTimers:[String:Task<Void,Never>]=[:]
    private var requestCount=0
    private var timerCount=0
    private var closed=false
    private(set) var support:[String:[String]]=[:]
    private(set) var updateNote=""
    func initialize(_ source:LXSource,timeout:Double=8) async throws -> [String:[String]] {
        let bootstrap:String
        if let bootstrapOverride { bootstrap=bootstrapOverride }
        else {
            guard let url=Bundle.main.url(forResource:"lx-user-api-ios",withExtension:"js") else { throw MusicError.message("缺少 LX 协议资源") }
            bootstrap=try String(contentsOf:url,encoding:.utf8)
        }
        var metadata:[String:Any]=["name":source.name,"author":source.metadata.author,"version":source.metadata.version,
                                  "description":source.metadata.description,"homepage":source.metadata.homepage]
        metadata["rawScript"]=source.script
        let meta=try encode(metadata)
        let script=source.script
        let raw=try await wait(key:"inited",seconds:timeout) {
            self.worker.start(script:script,bootstrap:bootstrap,metadata:meta) { [weak self] action,raw in
                Task { @MainActor in self?.receive(action,raw) }
            }
        }
        support=try LXProtocol.capabilities(raw)
        return support
    }
    func resolve(_ track:Track,quality:String,timeout:Double=10) async throws -> String {
        let key=UUID().uuidString
        let info=try encode(LXProtocol.musicInfo(track))
        return try await wait(key:key,seconds:timeout) {
            self.worker.invoke("__nlMusicUrl",args:[key,track.platform.rawValue,info,quality])
        }
    }
    private func encode(_ data:[String:Any]) throws -> String {
        String(decoding:try JSONSerialization.data(withJSONObject:data),as:UTF8.self)
    }
    private func object(_ raw:String) -> [String:Any]? {
        (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any]
    }
    private func wait(key:String,seconds:Double,start:()->Bool) async throws -> String {
        try Task.checkCancellation()
        guard !closed,pending==nil else { throw MusicError.message("LX 引擎已关闭或忙碌") }
        return try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<String,Error>) in
                pending=continuation;pendingKey=key
                let delay=UInt64(max(0.1,min(15,seconds))*1_000_000_000)
                timer=Task { [weak self] in
                    do { try await Task.sleep(nanoseconds:delay) } catch { return }
                    guard let self,self.pendingKey==key else { return }
                    self.finish(.failure(MusicError.message(key=="inited" ? "LX 初始化超时" : "LX 音源解析超时")))
                    self.close()
                }
                if !start() { finish(.failure(MusicError.message("LX 执行队列忙碌，请检查脚本或重新启动 App"))) }
            }
        },onCancel:{ [weak self] in Task { @MainActor in self?.close() } })
    }
    private func finish(_ result:Result<String,Error>) {
        timer?.cancel();timer=nil;pendingKey=nil
        let current=pending;pending=nil;current?.resume(with:result)
    }
    func close() {
        guard !closed else { return }
        closed=true
        finish(.failure(CancellationError()))
        for task in http.values { task.cancel() };http.removeAll()
        for task in jsTimers.values { task.cancel() };jsTimers.removeAll()
        worker.stop()
    }
    private func respond(_ key:String,_ payload:[String:Any]) {
        guard !closed,let json=try? encode(payload) else { return }
        if !worker.invoke("__nlHttpResponse",args:[key,json]) {
            finish(.failure(MusicError.message("LX 执行队列已满")));close()
        }
    }
    private func receive(_ action:String,_ raw:String) {
        guard !closed else { return }
        switch action {
        case "inited": if pendingKey=="inited" { finish(.success(raw)) }
        case "scriptError":
            if pending != nil { finish(.failure(MusicError.message("LX 脚本错误：\(String(raw.prefix(180)))")));close() }
        case "updateAlert":
            updateNote=String((object(raw)?["log"] as? String ?? "").prefix(1024))
        case "musicUrl","error":
            guard let payload=object(raw),let key=payload["key"] as? String,pendingKey==key else { return }
            if action=="musicUrl",let url=payload["url"] as? String { finish(.success(url)) }
            else { finish(.failure(MusicError.message(String((payload["message"] as? String ?? "LX 解析失败").prefix(180))))) }
        case "http":
            guard let payload=object(raw),let key=payload["requestKey"] as? String,key.count<=128,
                  http[key]==nil,let url=payload["url"] as? String else { return }
            guard http.count<6,requestCount<32 else { respond(key,["error":"音源请求次数超限"]);return }
            requestCount+=1
            let options=payload["options"] as? [String:Any] ?? [:]
            http[key]=Task { [weak self] in
                let result:[String:Any]
                do { result=try await LXNetwork.scriptRequest(url,options:options) }
                catch { result=["error":String(error.localizedDescription.prefix(180))] }
                guard let self,!Task.isCancelled,!self.closed,self.http[key] != nil else { return }
                self.http.removeValue(forKey:key);self.respond(key,result)
            }
        case "cancel": http.removeValue(forKey:raw)?.cancel()
        case "timer":
            guard let p=object(raw),let key=p["key"] as? String,key.count<=128,jsTimers[key]==nil else { return }
            guard jsTimers.count<32,timerCount<128 else { return }
            timerCount+=1
            let value=(p["delay"] as? NSNumber)?.doubleValue ?? 0
            let delay=UInt64((value.isFinite ? min(15000,max(0,value)) : 0)*1_000_000)
            jsTimers[key]=Task { [weak self] in
                do { try await Task.sleep(nanoseconds:delay) } catch { return }
                guard let self,!self.closed else { return }
                self.jsTimers.removeValue(forKey:key)
                if !self.worker.invoke("__nlTimer",args:[key]) {
                    self.finish(.failure(MusicError.message("LX 执行队列已满")));self.close()
                }
            }
        case "cancelTimer": jsTimers.removeValue(forKey:raw)?.cancel()
        default: break
        }
    }
}
