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
struct RootScreen: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: Library
    @StateObject private var chrome = BottomChromeState()
    @State private var keyboardShown = false
    @State private var expanded = false
    @State private var tab = 0
    var body: some View {
        TabView(selection:$tab) {
            NavigationStack { HomeScreen() }.toolbar(.hidden,for:.tabBar).tabItem { Label("首页",systemImage:"house") }.tag(0)
            NavigationStack { PlaylistScreen() }.toolbar(.hidden,for:.tabBar).tabItem { Label("歌单",systemImage:"music.note.list") }.tag(1)
            NavigationStack { LibraryScreen() }.toolbar(.hidden,for:.tabBar).tabItem { Label("我的",systemImage:"heart") }.tag(2)
            NavigationStack { SettingsScreen() }.toolbar(.hidden,for:.tabBar).tabItem { Label("设置",systemImage:"gearshape") }.tag(3)
            NavigationStack { SearchScreen() }.toolbar(.hidden,for:.tabBar).tabItem { Label("搜索",systemImage:"magnifyingglass") }.tag(4)
        }
        .environmentObject(chrome)
        .safeAreaInset(edge:.bottom,spacing:0) {
            if !keyboardShown {
                FloatingChrome(tab:$tab,open:{expanded=true}).environmentObject(chrome)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) { _ in keyboardShown=true }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) { _ in keyboardShown=false;chrome.update(false,force:true) }
        .sheet(isPresented:$expanded) { NowPlayingScreen().environmentObject(player).environmentObject(library).environmentObject(settings).presentationDetents([.large]) }
        .alert("奶龙音乐",isPresented:Binding(get:{!expanded && (player.error != nil || library.error != nil)},set:{ if !$0 { player.error = nil; library.error = nil } })) {
            Button("确定",role:.cancel) { player.error = nil; library.error = nil }
        } message: { Text(player.error ?? library.error ?? "") }
        .task {
            if settings.autoRoute { await settings.measure() }
        }
    }
}
