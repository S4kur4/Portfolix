import AppKit
import SwiftUI

extension View {
    func portfolixHelp(_ text: String, placement: HelpTooltipPlacement = .top, isEnabled: Bool = true) -> some View {
        background {
            HoverHelpAnchor(text: text, placement: placement, isEnabled: isEnabled)
                .accessibilityHidden(true)
        }
        .accessibilityHint(isEnabled ? text : "")
    }
}

private struct HoverHelpAnchor: NSViewRepresentable {
    let text: String
    let placement: HelpTooltipPlacement
    let isEnabled: Bool

    func makeNSView(context: Context) -> HoverHelpView {
        HoverHelpView()
    }

    func updateNSView(_ view: HoverHelpView, context: Context) {
        if view.text != text {
            view.dismissTooltip()
            view.text = text
        }
        view.placement = placement
        view.isHelpEnabled = isEnabled
    }

    static func dismantleNSView(_ view: HoverHelpView, coordinator: ()) {
        view.dismissTooltip()
    }
}

enum HoverHelpLayout {
    static func frame(size: CGSize, anchor: CGRect, screen: CGRect, placement: HelpTooltipPlacement) -> CGRect {
        let gap = PortfolixSpacing.sm
        var origin: CGPoint
        switch placement {
        case .top:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
            if origin.y + size.height > screen.maxY - gap {
                origin.y = anchor.minY - gap - size.height
            }
        case .trailing:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
            if origin.x + size.width > screen.maxX - gap {
                origin.x = anchor.minX - gap - size.width
            }
        }
        origin.x = max(screen.minX + gap, min(origin.x, screen.maxX - gap - size.width))
        origin.y = max(screen.minY + gap, min(origin.y, screen.maxY - gap - size.height))
        return CGRect(origin: origin, size: size)
    }
}

// A separate, non-interactive window avoids clipping tips inside scroll views and the narrow sidebar.
final class HoverHelpView: NSView {
    var text = ""
    var isHelpEnabled = true {
        didSet { if !isHelpEnabled { dismissTooltip() } }
    }
    var placement: HelpTooltipPlacement = .top
    private var pendingShow: DispatchWorkItem?
    private var tooltipWindow: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    isolated deinit {
        dismissTooltip()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismissTooltip()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        dismissTooltip()
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewDidHide() {
        dismissTooltip()
        super.viewDidHide()
    }

    override func mouseEntered(with event: NSEvent) {
        dismissTooltip()
        guard isHelpEnabled else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.showTooltip(requirePointerInside: true)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        dismissTooltip()
    }

    private func isPointerInsideVisibleBounds(in window: NSWindow) -> Bool {
        let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return !visibleRect.isEmpty && visibleRect.contains(localPoint)
    }

    func showTooltip(requirePointerInside: Bool = false) {
        pendingShow = nil
        guard isHelpEnabled, tooltipWindow == nil, let window, window.isKeyWindow,
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty,
              !requirePointerInside || isPointerInsideVisibleBounds(in: window),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let appearance = NSApp?.appearance ?? window.effectiveAppearance
        let colorScheme: ColorScheme = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let host = NSHostingView(rootView: HelpTooltipBubble(text: text).environment(\.colorScheme, colorScheme))
        host.appearance = appearance
        let size = host.fittingSize
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        guard let screen = window.screen else { return }
        let frame = HoverHelpLayout.frame(size: size, anchor: anchor, screen: screen.visibleFrame, placement: placement)
        let panel = HoverHelpPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.appearance = appearance
        panel.contentView = host
        panel.setFrame(frame, display: false)
        tooltipWindow = panel
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissTooltip() }
            })
        }
        // Dismiss immediately whenever any enclosing scroll view scrolls (manual or programmatic).
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                observers.append(center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismissTooltip() }
                })
                let clipView = scrollView.contentView
                clipView.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismissTooltip() }
                })
            }
            ancestor = current.superview
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissTooltip() }
            return event
        }
    }

    func dismissTooltip() {
        pendingShow?.cancel()
        pendingShow = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let panel = tooltipWindow {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.close()
            tooltipWindow = nil
        }
    }
}

private final class HoverHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
