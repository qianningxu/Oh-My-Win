import AppKit
import SwiftUI

struct WindowTabNativeGlass: View {
    let height: CGFloat

    var body: some View {
        if #available(macOS 26.0, *) {
            WindowTabGlassEffect(cornerRadius: height / 2)
        } else {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Capsule(style: .continuous))
        }
    }
}

@available(macOS 26.0, *)
private struct WindowTabGlassEffect: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.tintColor = nil
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.style = .regular
        view.tintColor = nil
        view.cornerRadius = cornerRadius
    }
}
