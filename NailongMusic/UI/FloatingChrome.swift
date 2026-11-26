import SwiftUI
import UIKit

@MainActor final class BottomChromeState: ObservableObject {
    @Published private(set) var compact=false
    private var lastChange=Date.distantPast
    func update(_ compact:Bool,force:Bool=false) {
        guard self.compact != compact,force || Date().timeIntervalSince(lastChange)>0.32 else { return }
        lastChange=Date();self.compact=compact
    }
}

private struct ChromeScrollObserver: ViewModifier {
    @EnvironmentObject var chrome:BottomChromeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accumulated:CGFloat=0
    @State private var lastDrag:CGFloat=0
    func body(content:Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for:CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { old,new in
                guard new.isFinite,old.isFinite else { return }
                if new<=5 { accumulated=0;change(false,force:true);return }
                consume(new-old)
            }
        } else {
            // Simultaneous observation, not a replacement for native scroll gestures.
            content.simultaneousGesture(DragGesture(minimumDistance:12).onChanged { value in
                guard abs(value.translation.height)>abs(value.translation.width)*1.25 else { return }
                let current = -value.translation.height
                consume(current-lastDrag);lastDrag=current
            }.onEnded { _ in lastDrag=0;accumulated=0 })
        }
    }
    private func consume(_ delta:CGFloat) {
        guard abs(delta)>0.3 else { return }
        if (accumulated>0 && delta<0) || (accumulated<0 && delta>0) { accumulated=0 }
        accumulated+=delta
        if accumulated>=28 { change(true);accumulated=0 }
        else if accumulated<=(-22) { change(false);accumulated=0 }
    }
    private func change(_ compact:Bool,force:Bool=false) {
        withAnimation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.86)) { chrome.update(compact,force:force) }
    }
}
extension View {
    func scrollChrome() -> some View { modifier(ChromeScrollObserver()).toolbar(.hidden,for:.tabBar) }
    @ViewBuilder func floatingGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular,in:.capsule)
        } else {
            self.background(.regularMaterial,in:Capsule())
                .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.12),lineWidth:0.5) }
        }
    }
}
struct FloatingChrome: View {
    @EnvironmentObject var chrome:BottomChromeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var tab:Int
    let open:()->Void
    private let items:[(String,String,String)]=[
        ("首页","house","house.fill"),
        ("歌单","music.note.list","music.note.list"),
        ("我的","heart","heart.fill"),
        ("设置","gearshape","gearshape.fill")
    ]
    var body:some View {
        VStack(spacing:chrome.compact ? 4 : 8) {
            MiniPlayer(compact:chrome.compact,open:open)
                .frame(maxWidth:chrome.compact ? 300 : 560)
            HStack(spacing:10) {
                HStack(spacing:2) {
                    ForEach(items.indices,id:\.self) { index in
                        tabButton(index,items[index].0,items[index].1,items[index].2)
                    }
                }.padding(5).frame(maxWidth:chrome.compact ? 252 : 450).floatingGlass()
                Button { select(4) } label: {
                    VStack(spacing:3) {
                        Image(systemName:"magnifyingglass").font(.system(size:chrome.compact ? 21 : 23,weight:.semibold))
                        if !chrome.compact { Text("搜索").font(.caption2.weight(.medium)) }
                    }.frame(width:chrome.compact ? 46 : 60,height:chrome.compact ? 46 : 58)
                        .foregroundStyle(tab==4 ? Color.accentColor : Color.primary)
                        .background {
                            if tab==4 { Capsule().fill(Color.accentColor.opacity(0.13)) }
                        }
                }.buttonStyle(.plain).floatingGlass().accessibilityLabel("搜索")
                    .accessibilityAddTraits(tab==4 ? .isSelected : [])
            }.frame(maxWidth:560)
        }
        .padding(.horizontal,12)
        .padding(.top,chrome.compact ? 1 : 3)
        .padding(.bottom,chrome.compact ? 1 : 8)
        .frame(maxWidth:.infinity)
        .animation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.86),value:chrome.compact)
    }
    private func tabButton(_ index:Int,_ name:String,_ symbol:String,_ selectedSymbol:String) -> some View {
        Button { select(index) } label: {
            VStack(spacing:3) {
                Image(systemName:tab==index ? selectedSymbol : symbol)
                    .font(.system(size:chrome.compact ? 20 : 22,weight:tab==index ? .semibold : .regular))
                if !chrome.compact { Text(name).font(.caption2.weight(tab==index ? .semibold : .regular)).lineLimit(1) }
            }
            .frame(maxWidth:.infinity)
            .frame(height:chrome.compact ? 44 : 48)
            .foregroundStyle(tab==index ? Color.accentColor : Color.primary)
            .background { if tab==index { Capsule().fill(Color.accentColor.opacity(0.13)) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
         .accessibilityLabel(name)
         .accessibilityAddTraits(tab==index ? .isSelected : [])
    }
    private func select(_ index:Int) {
        withAnimation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.86)) {
            tab=index;chrome.update(false,force:true)
        }
    }
}
