import SwiftUI
import AppKit

/// Shows a floating notification pill, a pulsing screen-edge glow, and plays a sound.
final class AlertPresenter {
    static let shared = AlertPresenter()
    private var windows: [NSWindow] = []
    private var dismissWork: DispatchWorkItem?

    func show(title: String, message: String, symbol: String, color: Color,
              sound: String?, glow: Bool = true) {
        closeNow()

        if glow {
            for screen in NSScreen.screens {
                windows.append(makeWindow(frame: screen.frame, clickThrough: true,
                                          content: GlowView(color: color)))
            }
        }

        if let screen = NSScreen.main {
            let size = NSSize(width: 460, height: 130)
            let frame = NSRect(x: screen.frame.midX - size.width / 2,
                               y: screen.visibleFrame.maxY - size.height,
                               width: size.width, height: size.height)
            windows.append(makeWindow(frame: frame, clickThrough: false,
                                      content: AlertPill(title: title, message: message,
                                                         symbol: symbol, color: color)))
        }

        if let sound { NSSound(named: NSSound.Name(sound))?.play() }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ws.forEach { $0.animator().alphaValue = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ws.forEach { $0.close() } }
    }

    private func closeNow() {
        dismissWork?.cancel()
        windows.forEach { $0.close() }
        windows = []
    }

    private func makeWindow<Content: View>(frame: NSRect, clickThrough: Bool,
                                           content: Content) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .screenSaver
        w.ignoresMouseEvents = clickThrough
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: content)
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
        return w
    }
}

struct GlowView: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Rectangle()
            .strokeBorder(color, lineWidth: 70)
            .blur(radius: 50)
            .opacity(on ? 0.85 : 0.1)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatCount(7, autoreverses: true)) { on = true }
            }
    }
}

struct AlertPill: View {
    let title: String
    let message: String
    let symbol: String
    let color: Color
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color).frame(width: 42, height: 42)
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .offset(y: shown ? 0 : -50)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { shown = true }
        }
        .onTapGesture { AlertPresenter.shared.dismiss() }
    }
}
