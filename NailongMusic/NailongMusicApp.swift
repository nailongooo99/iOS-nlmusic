import SwiftUI
import UIKit

@main @MainActor struct NailongMusicApp: App {
    @StateObject private var library: Library
    @StateObject private var settings: Settings
    @StateObject private var player: Player
    init() {
        let library = Library(), settings = Settings()
        _library = StateObject(wrappedValue:library)
        _settings = StateObject(wrappedValue:settings)
        _player = StateObject(wrappedValue:Player(library:library,settings:settings))
        URLCache.shared = URLCache(memoryCapacity:32*1024*1024,diskCapacity:128*1024*1024)
    }
    var body: some Scene {
        WindowGroup {
            RootScreen().environmentObject(library).environmentObject(settings).environmentObject(player)
                .preferredColorScheme(settings.colorScheme)
                .tint(Color(red:0.13,green:0.53,blue:0.49))
        }
    }
}
@MainActor struct RootScreen: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: Library
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chrome = BottomChromeState()
    @StateObject private var analyticsPages = AnalyticsPages()
    @State private var keyboardShown = false
    @State private var expanded = false
    @State private var tab = 0
    private var analyticsPage: String {
        if expanded { return "player" }
        return analyticsPages.page(for:tab) ?? ["home","playlists","mine","settings","search"][tab]
    }
    var body: some View {
        Group {
            if #available(iOS 26.0, *) { modernTabs }
            else { legacyTabs }
        }
        .environmentObject(chrome)
        .environmentObject(analyticsPages)
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) { _ in keyboardShown=true }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) { _ in keyboardShown=false;chrome.update(false,force:true) }
        .onChange(of:tab) { _ in chrome.update(false,force:true) }
        .sheet(isPresented:$expanded) {
            NowPlayingScreen().environmentObject(player).environmentObject(library).environmentObject(settings)
                .environmentObject(analyticsPages).presentationDetents([.large])
        }
        .alert("奶龙音乐",isPresented:Binding(get:{!expanded && (player.error != nil || library.error != nil)},set:{ if !$0 { player.error = nil; library.error = nil } })) {
            Button("确定",role:.cancel) { player.error = nil; library.error = nil }
        } message: { Text(player.error ?? library.error ?? "") }
        .onAppear { synchronizeAnalytics() }
        .task(id:analyticsPage) {
            // Coalesce SwiftUI parent disappearance and child appearance in one transition.
            do { try await Task.sleep(nanoseconds:80_000_000) } catch { return }
            synchronizeAnalytics()
        }
        .onChange(of:settings.analyticsEnabled) { enabled in
            if !enabled { ActivityAnalytics.shared.disable() }
            else { synchronizeAnalytics() }
        }
        .onChange(of:scenePhase) { phase in
            if phase == .background { ActivityAnalytics.shared.foregroundStopped() }
            else if phase == .active { synchronizeAnalytics() }
        }
        .task {
            if settings.autoRoute { await settings.measure() }
        }
    }
    private func synchronizeAnalytics() {
        guard scenePhase == .active, settings.analyticsEnabled else { return }
        ActivityAnalytics.shared.visit(analyticsPage)
    }
    @available(iOS 26.0, *)
    private var modernTabs: some View {
        let tabs = TabView(selection:$tab) {
            Tab("首页",systemImage:"house",value:0) { modernPage(0) { HomeScreen() } }
            Tab("歌单",systemImage:"music.note.list",value:1) { modernPage(1) { PlaylistScreen() } }
            Tab("我的",systemImage:"heart",value:2) { modernPage(2) { LibraryScreen() } }
            Tab("设置",systemImage:"gearshape",value:3) { modernPage(3) { SettingsScreen() } }
            Tab(value:4,role:.search) { modernPage(4) { SearchScreen() } }
        }.tabBarMinimizeBehavior(.onScrollDown)
        return Group {
            if #available(iOS 26.1, *) {
                tabs.tabViewBottomAccessory(isEnabled:player.current != nil && !keyboardShown) {
                    SystemMiniPlayer(open:{expanded=true})
                }
            } else {
                tabs.tabViewBottomAccessory {
                    if player.current != nil && !keyboardShown { SystemMiniPlayer(open:{expanded=true}) }
                }
            }
        }
    }
    private var legacyTabs: some View {
        TabView(selection:$tab) {
            legacyPage(0) { HomeScreen() }.tabItem { Label("首页",systemImage:"house") }.tag(0)
            legacyPage(1) { PlaylistScreen() }.tabItem { Label("歌单",systemImage:"music.note.list") }.tag(1)
            legacyPage(2) { LibraryScreen() }.tabItem { Label("我的",systemImage:"heart") }.tag(2)
            legacyPage(3) { SettingsScreen() }.tabItem { Label("设置",systemImage:"gearshape") }.tag(3)
            legacyPage(4) { SearchScreen() }.tabItem { Label("搜索",systemImage:"magnifyingglass") }.tag(4)
        }
    }
    private func modernPage<Content:View>(_ index:Int,@ViewBuilder content:()->Content) -> some View {
        NavigationStack { content() }.environment(\.analyticsTab,index)
    }
    private func legacyPage<Content:View>(_ index:Int,@ViewBuilder content:()->Content) -> some View {
        NavigationStack { content() }
            .environment(\.analyticsTab,index)
            .safeAreaInset(edge:.bottom,spacing:0) {
                if player.current != nil && !keyboardShown {
                    MiniPlayer(compact:chrome.compact,open:{expanded=true})
                        .background(.regularMaterial)
                        .overlay(alignment:.top) { Divider() }
                }
            }
    }
}
