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
    @ViewBuilder func scrollChrome() -> some View {
        if #available(iOS 26.0, *) {
            // The system owns the minimization, scroll coordination and safe areas.
            self
        } else {
            modifier(ChromeScrollObserver())
        }
    }
}

// On iOS 26 and later, the system relocates this accessory inline as the
// system tab bar minimizes; do not draw another glass background.
@available(iOS 26.0, *)
struct SystemMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let open: () -> Void
    var body: some View {
        MiniPlayer(compact:placement == .inline,open:open)
    }
}
