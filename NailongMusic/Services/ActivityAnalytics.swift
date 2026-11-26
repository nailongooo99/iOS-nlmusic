import Foundation
import SwiftUI
import UIKit
import Darwin

private final class AnalyticsNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(nil)
    }
}

// Android ActivityAnalytics parity: in-memory bounded queue, per-install/session/
// visit UUIDs, cumulative integer seconds, 30s heartbeat, and no retry persistence.
// All lifecycle state is main-actor isolated; URLSession runs I/O asynchronously.
@MainActor final class ActivityAnalytics {
    static let shared=ActivityAnalytics()
    private static let installationKey="nailong_analytics_v1.installation"
    private let defaults=UserDefaults.standard
    private let clock=ContinuousClock()
    private let transport:URLSession
    private var sessionID=UUID().uuidString.lowercased()
    private var generation:UInt64=0
    private var active:Visit?
    private var queue:[Report]=[]
    private var worker:Task<Void,Never>?
    private var heartbeat:Task<Void,Never>?
    private var backgroundTask:UIBackgroundTaskIdentifier = .invalid
    private struct Visit {
        let installation:String
        let session:String
        let id:String
        let page:String
        let started:ContinuousClock.Instant
    }
    private struct Report {
        let visit:Visit
        let elapsed:Int
        let closed:Bool
        let generation:UInt64
    }
    private init() {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=5
        configuration.timeoutIntervalForResource=5
        configuration.httpCookieStorage=nil
        configuration.httpShouldSetCookies=false
        configuration.urlCredentialStorage=nil
        configuration.urlCache=nil
        transport=URLSession(configuration:configuration,delegate:AnalyticsNoRedirect(),delegateQueue:nil)
    }
    private var enabled:Bool { defaults.object(forKey:"analyticsEnabled") as? Bool ?? true }
    func visit(_ rawPage:String) {
        guard enabled else { return }
        endBackgroundTask()
        let page=AnalyticsProtocol.page(rawPage)
        if active?.page==page { return }
        leave()
        let installation:String
        if let existing=defaults.string(forKey:Self.installationKey),UUID(uuidString:existing) != nil {
            installation=existing
        } else {
            installation=UUID().uuidString.lowercased()
            defaults.set(installation,forKey:Self.installationKey)
        }
        let next=Visit(installation:installation,session:sessionID,id:UUID().uuidString.lowercased(),page:page,started:clock.now)
        active=next
        publish(closed:false)
        heartbeat=Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:UInt64(AnalyticsProtocol.heartbeatSeconds)*1_000_000_000) } catch { return }
                guard let self,self.active?.id==next.id,self.enabled else { return }
                self.publish(closed:false)
            }
        }
    }
    func foregroundStopped() {
        leave()
        sessionID=UUID().uuidString.lowercased()
        // Best effort to finish the final foreground visit before suspension.
        // No new visits or periodic heartbeats run in the background.
        if worker != nil,backgroundTask == .invalid {
            backgroundTask=UIApplication.shared.beginBackgroundTask(withName:"Finish usage visit") { [weak self] in
                Task { @MainActor in
                    guard let self,self.backgroundTask != .invalid else { return }
                    self.generation &+= 1
                    self.worker?.cancel();self.worker=nil
                    self.queue.removeAll()
                    self.endBackgroundTask()
                }
            }
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let token=backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(token)
    }
    func disable() {
        generation &+= 1
        heartbeat?.cancel();heartbeat=nil
        worker?.cancel();worker=nil
        queue.removeAll(keepingCapacity:true)
        active=nil
        sessionID=UUID().uuidString.lowercased()
        defaults.removeObject(forKey:Self.installationKey)
        endBackgroundTask()
    }
    private func leave() {
        heartbeat?.cancel();heartbeat=nil
        publish(closed:true)
        active=nil
    }
    private func publish(closed:Bool) {
        guard enabled,let visit=active,queue.count<AnalyticsProtocol.queueCapacity else { return }
        let seconds=visit.started.duration(to:clock.now).components.seconds
        queue.append(Report(visit:visit,elapsed:Int(clamping:seconds),closed:closed,generation:generation))
        drain()
    }
    private func drain() {
        guard worker==nil else { return }
        let currentGeneration=generation
        worker=Task { [weak self] in
            guard let self else { return }
            defer { if self.generation==currentGeneration { self.worker=nil;self.endBackgroundTask() } }
            while !Task.isCancelled,self.generation==currentGeneration,!self.queue.isEmpty {
                let report=self.queue.removeFirst()
                guard self.enabled,report.generation==self.generation else { continue }
                await self.send(report)
            }
        }
    }
    // uname.machine is a non-unique device model identifier, not a serial or IDFA.
    // Apple does not expose an Android SDK_INT or SoC model via a public equivalent.
    // Keep the same field types, use the iOS major OS number and an empty SoC model.
    private func deviceModel() -> String {
        #if targetEnvironment(simulator)
        return UIDevice.current.model+" Simulator"
        #else
        var info=utsname()
        guard uname(&info)==0 else { return UIDevice.current.model }
        let machine=withUnsafeBytes(of:&info.machine) { bytes in
            String(decoding:bytes.prefix(while:{$0 != 0}),as:UTF8.self)
        }
        return machine.isEmpty ? UIDevice.current.model : machine
        #endif
    }
    private func send(_ report:Report) async {
        guard enabled,report.generation==generation,!Task.isCancelled,
              let url=URL(string:AnalyticsProtocol.endpoint),url.scheme=="https",
              url.host != nil,url.user==nil,url.password==nil,url.fragment==nil else { return }
        let version=ProcessInfo.processInfo.operatingSystemVersion
        let appVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0"
        let payload=AnalyticsProtocol.payload(installation:report.visit.installation,session:report.visit.session,visit:report.visit.id,
            page:report.visit.page,elapsed:report.elapsed,closed:report.closed,model:deviceModel(),brand:"Apple",soc:"",vendor:"Apple",
            os:UIDevice.current.systemVersion,sdk:version.majorVersion,app:appVersion)
        guard let data=try? JSONEncoder().encode(payload) else { return }
        var request=URLRequest(url:url,timeoutInterval:5)
        request.httpMethod="POST"
        request.httpBody=data
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        guard enabled,report.generation==generation,!Task.isCancelled else { return }
        // Best effort, no persistent retry queue or response logging.
        _=try? await transport.data(for:request)
    }
}

private struct AnalyticsTabKey:EnvironmentKey {
    static let defaultValue:Int = -1
}
extension EnvironmentValues {
    var analyticsTab:Int {
        get { self[AnalyticsTabKey.self] }
        set { self[AnalyticsTabKey.self]=newValue }
    }
}
@MainActor final class AnalyticsPages:ObservableObject {
    struct Entry:Equatable { let id:UUID;let tab:Int;let page:String }
    @Published private var stack:[Entry]=[]
    func enter(_ id:UUID,tab:Int,page:String) {
        guard tab>=0 else { return }
        stack.removeAll{$0.id==id}
        stack.append(.init(id:id,tab:tab,page:AnalyticsProtocol.page(page)))
    }
    func leave(_ id:UUID) { stack.removeAll{$0.id==id} }
    func page(for tab:Int) -> String? { stack.last(where:{$0.tab==tab})?.page }
}
private struct AnalyticsPageModifier:ViewModifier {
    @EnvironmentObject private var pages:AnalyticsPages
    @Environment(\.analyticsTab) private var tab
    @State private var id=UUID()
    let page:String
    func body(content:Content) -> some View {
        content.onAppear { pages.enter(id,tab:tab,page:page) }
            .onDisappear { pages.leave(id) }
    }
}
extension View {
    func analyticsPage(_ page:String) -> some View {
        modifier(AnalyticsPageModifier(page:page))
    }
}
