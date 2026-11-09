import AppKit
import Combine
import SwiftUI
import QuartzCore

/// Space occupied by the physical camera housing on the panel's current display.
struct NotchHeaderLayout: Sendable {
    var reservedWidth: CGFloat
    var bandHeight: CGFloat
    var maximumPanelHeight: CGFloat

    static let fallback = NotchHeaderLayout(reservedWidth: 180, bandHeight: 32, maximumPanelHeight: 900)

    @MainActor
    static func on(_ screen: NSScreen, panelWidth: CGFloat) -> NotchHeaderLayout {
        let maximumHeight = max(1, screen.frame.maxY - max(screen.frame.minY, screen.visibleFrame.minY) - 16)
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchHeaderLayout(
                reservedWidth: min(panelWidth, max(0, right.minX - left.maxX) + 24),
                bandHeight: max(32, screen.safeAreaInsets.top),
                maximumPanelHeight: maximumHeight
            )
        }
        return NotchHeaderLayout(reservedWidth: 0, bandHeight: 36, maximumPanelHeight: maximumHeight)
    }
}

private struct NotchHeaderLayoutKey: EnvironmentKey {
    static let defaultValue = NotchHeaderLayout.fallback
}

extension EnvironmentValues {
    var notchHeaderLayout: NotchHeaderLayout {
        get { self[NotchHeaderLayoutKey.self] }
        set { self[NotchHeaderLayoutKey.self] = newValue }
    }
}

/// Owns Lunera's menu-bar entry and its screen-attached calendar panel.
@MainActor
final class NotchPanelController: NSObject {
    static let panelWidth: CGFloat = 520

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: NotchPanel
    private let onGoToToday: () -> Void
    private let onPreferences: () -> Void
    private let canCheckForUpdates: () -> Bool
    private let onCheckForUpdates: () -> Void
    private let store: CalendarStore
    private var storeSubscription: AnyCancellable?
    private var activeScreen: NSScreen?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var isPresented = false
    private var animationID = 0
    private var targetFrame: NSRect?
    private var sizeUpdateScheduled = false

    init<Content: View>(content: Content, store: CalendarStore, onGoToToday: @escaping () -> Void,
                        onPreferences: @escaping () -> Void = {},
                        canCheckForUpdates: @escaping () -> Bool = { false },
                        onCheckForUpdates: @escaping () -> Void = {}) {
        self.store = store
        self.onPreferences = onPreferences
        self.canCheckForUpdates = canCheckForUpdates
        self.onCheckForUpdates = onCheckForUpdates
        let initialLayout = CalendarPanelLayout(
            weekCount: store.days.count / 7,
            headerHeight: NotchHeaderLayout.fallback.bandHeight,
            hasCalendarAccess: store.authorization == .authorized,
            allDayCount: store.selectedEvents.filter(\.isAllDay).count,
            timedEventCount: store.selectedEvents.filter { !$0.isAllDay }.count,
            maximumHeight: NotchHeaderLayout.fallback.maximumPanelHeight
        )
        panel = NotchPanel(content: AnyView(content), size: NSSize(width: Self.panelWidth, height: initialLayout.height))
        self.onGoToToday = onGoToToday
        super.init()
        if let button = statusItem.button {
            button.image = Self.statusBarImage()
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Lunera")
            button.toolTip = "Lunera — click to open, Space for today, right-click for options"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide(animated: false) }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide(animated: false) }
        }
        // @Published emits before mutation. Hop to the main actor so all of the
        // current date/permission/event changes are committed before measuring.
        storeSubscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleSizeUpdate() }
        }
    }

    private static func statusBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let context = NSGraphicsContext.current?.cgContext
            context?.saveGState()
            context?.translateBy(x: 9, y: 9)
            context?.scaleBy(x: 1.14, y: 1.14)
            context?.translateBy(x: -9, y: -9)
            defer { context?.restoreGState() }
            NSColor.black.setFill()

            // The crescent and four calendar dots are a simplified version of the app icon.
            let crescent = NSBezierPath()
            crescent.move(to: NSPoint(x: 11.6, y: 3))
            crescent.curve(to: NSPoint(x: 3.1, y: 9.1),
                           controlPoint1: NSPoint(x: 7, y: 1),
                           controlPoint2: NSPoint(x: 3, y: 4.5))
            crescent.curve(to: NSPoint(x: 14.1, y: 12.8),
                           controlPoint1: NSPoint(x: 3, y: 14.3),
                           controlPoint2: NSPoint(x: 10.5, y: 17))
            crescent.curve(to: NSPoint(x: 5.8, y: 8.8),
                           controlPoint1: NSPoint(x: 11.1, y: 14.9),
                           controlPoint2: NSPoint(x: 6.5, y: 12.5))
            crescent.curve(to: NSPoint(x: 11.6, y: 3),
                           controlPoint1: NSPoint(x: 5.3, y: 5.4),
                           controlPoint2: NSPoint(x: 8.5, y: 2.8))
            crescent.close()
            crescent.fill()

            for x in [8.6, 11.1] {
                for y in [6.5, 9.0] {
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(withTitle: isPresented ? "Hide Lunera" : "Open Lunera", action: #selector(toggleFromMenu), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
            let checkUpdates = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
            checkUpdates.isEnabled = canCheckForUpdates()
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Lunera", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            toggle()
        }
    }

    @objc private func toggleFromMenu() { toggle() }
    @objc private func openPreferences() { onPreferences() }
    @objc private func checkForUpdatesFromMenu() {
        guard canCheckForUpdates() else { return }
        hide(animated: false)
        onCheckForUpdates()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func toggle() {
        if isPresented { hide() } else { show() }
    }

    func show() {
        guard !isPresented,
              let screen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        // Reset the visible date and refresh external calendar changes before
        // calculating the expanded panel's height.
        store.goToToday()
        let continuing = panel.isVisible && activeScreen == screen
        isPresented = true
        activeScreen = screen
        panel.surface.configure(for: screen)
        move(to: frame(on: screen), motion: .open, continuing: continuing)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    func hide(animated: Bool = true) {
        guard isPresented || (!animated && panel.isVisible) else { return }
        isPresented = false
        animationID += 1
        let generation = animationID
        targetFrame = nil
        removeEventMonitors()
        guard animated else {
            panel.orderOut(nil)
            return
        }
        panel.surface.morph(to: panel.surface.collapsedSize, motion: .close) { [weak self] in
            guard let self, self.animationID == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    private func move(to target: NSRect, motion: PanelMotion, continuing: Bool = true) {
        animationID += 1
        let generation = animationID
        targetFrame = target

        // Keep enough canvas for the entire outgoing shape when shrinking.
        // Both the hosted content and the mask use the screen's top edge as their origin.
        let canvasHeight = continuing ? max(panel.frame.height, target.height) : target.height
        let canvas = NSRect(x: target.minX, y: target.maxY - canvasHeight,
                            width: target.width, height: canvasHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(canvas, display: false)
        panel.surface.place(canvas: canvas.size)
        if !continuing { panel.surface.resetToNotch() }
        CATransaction.commit()
        panel.surface.morph(to: target.size, motion: motion) { [weak self] in
            guard let self, self.animationID == generation, self.isPresented else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.panel.setFrame(target, display: false)
            self.panel.surface.place(canvas: target.size)
            CATransaction.commit()
        }
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let header = NotchHeaderLayout.on(screen, panelWidth: Self.panelWidth)
        let layout = CalendarPanelLayout(
            weekCount: store.days.count / 7,
            headerHeight: header.bandHeight,
            hasCalendarAccess: store.authorization == .authorized,
            allDayCount: store.selectedEvents.filter(\.isAllDay).count,
            timedEventCount: store.selectedEvents.filter { !$0.isAllDay }.count,
            maximumHeight: header.maximumPanelHeight
        )
        return NSRect(x: screen.frame.midX - Self.panelWidth / 2,
                      y: screen.frame.maxY - layout.height,
                      width: Self.panelWidth, height: layout.height)
    }

    private func scheduleSizeUpdate() {
        guard !sizeUpdateScheduled else { return }
        sizeUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeUpdateScheduled = false
            self.updateSize()
        }
    }

    private func updateSize() {
        guard isPresented, let screen = activeScreen else { return }
        let targetFrame = frame(on: screen)
        guard self.targetFrame != targetFrame else { return }
        move(to: targetFrame, motion: .resize)
    }

    private func screenAtMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            // Let the status button's own action perform the toggle, including right-click.
            if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                self.hide()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented, self.panel.isKeyWindow,
                  event.window == nil || event.window === self.panel else { return event }
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let editingText = (self.panel.firstResponder as? NSTextView)?.isFieldEditor == true
            if modifiers == .command, event.charactersIgnoringModifiers == ",", !editingText {
                if !event.isARepeat { self.onPreferences() }
                return nil
            }
            if event.keyCode == 49, modifiers.isEmpty, !editingText {
                if !event.isARepeat { self.onGoToToday() }
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }
}

/// A borderless key-capable panel: menu-bar controls and Escape remain usable.
@MainActor
private final class NotchPanel: NSPanel {
    let surface: NotchSurfaceView
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // This panel deliberately starts above the menu bar's safe content area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init(content: AnyView, size: NSSize) {
        surface = NotchSurfaceView(content: content, size: size)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        contentView = surface
    }
}

private enum PanelMotion {
    case open, close, resize

    var duration: CFTimeInterval {
        switch self {
        case .open: 0.46
        case .close: 0.32
        case .resize: 0.34
        }
    }

    // Sample a critically damped spring, normalized to land on the exact endpoint.
    func progress(_ t: Double, horizontal: Bool) -> CGFloat {
        let response: Double
        switch self {
        case .open: response = horizontal ? 10 : 7
        case .close: response = horizontal ? 6 : 9
        case .resize: response = 7.5
        }
        func step(_ x: Double) -> Double { 1 - (1 + x) * exp(-x) }
        return step(response * t) / step(response)
    }
}

@MainActor
private final class NotchSurfaceView: NSView {
    private let silhouette = CAShapeLayer()
    private let originalContent: AnyView
    private let host: NSHostingView<AnyView>
    private(set) var collapsedSize = NSSize(width: 200, height: 24)
    private var contentHeight = NotchHeaderLayout.fallback.maximumPanelHeight

    init(content: AnyView, size: NSSize) {
        originalContent = content
        host = NSHostingView(rootView: AnyView(content.environment(\.notchHeaderLayout, .fallback)))
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        silhouette.anchorPoint = CGPoint(x: 0, y: 1)
        silhouette.fillColor = NSColor.white.cgColor
        layer?.mask = silhouette
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        addSubview(host)
        place(canvas: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(for screen: NSScreen) {
        let header = NotchHeaderLayout.on(screen, panelWidth: NotchPanelController.panelWidth)
        contentHeight = header.maximumPanelHeight
        collapsedSize = header.reservedWidth > 0
            ? NSSize(width: max(160, header.reservedWidth), height: screen.safeAreaInsets.top)
            : NSSize(width: 200, height: 24)
        host.rootView = AnyView(originalContent.environment(\.notchHeaderLayout, header))
    }

    func place(canvas: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Mask coordinates grow down from y = 0 into negative y. Resizing the
        // canvas only moves the layer's anchor, never the path's top edge.
        silhouette.bounds = CGRect(x: 0, y: -canvas.height, width: canvas.width, height: canvas.height)
        silhouette.position = CGPoint(x: 0, y: canvas.height)
        host.frame = CGRect(x: 0, y: canvas.height - contentHeight,
                            width: canvas.width, height: contentHeight)
        host.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    func resetToNotch() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.removeAllAnimations()
        host.layer?.removeAnimation(forKey: "lunera.fade")
        silhouette.path = path(size: collapsedSize)
        host.layer?.opacity = 0
        CATransaction.commit()
    }

    func morph(to size: CGSize, motion: PanelMotion, completion: @escaping @MainActor () -> Void) {
        let visiblePath = silhouette.animation(forKey: "lunera.shape") == nil
            ? silhouette.path : (silhouette.presentation()?.path ?? silhouette.path)
        let start = visiblePath?.boundingBoxOfPath.size ?? collapsedSize
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { Task { @MainActor in completion() } }
        silhouette.removeAnimation(forKey: "lunera.shape")
        silhouette.path = path(size: size)
        if !reduced && start != size {
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = (0...48).map { index -> CGPath in
                let t = Double(index) / 48
                return path(size: CGSize(
                    width: start.width + (size.width - start.width) * motion.progress(t, horizontal: true),
                    height: start.height + (size.height - start.height) * motion.progress(t, horizontal: false)
                ))
            }
            animation.duration = motion.duration
            animation.calculationMode = .linear
            silhouette.add(animation, forKey: "lunera.shape")
        }
        if motion != .resize, let content = host.layer {
            let opacity = content.animation(forKey: "lunera.fade") == nil
                ? content.opacity : (content.presentation()?.opacity ?? content.opacity)
            let target: Float = motion == .close ? 0 : 1
            content.opacity = target
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = target
            fade.duration = reduced ? 0.10 : (motion == .open ? 0.24 : 0.14)
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            content.add(fade, forKey: "lunera.fade")
        }
        CATransaction.commit()
    }

    /// Both paths have identical control points/counts, allowing Core Animation to
    /// interpolate the contour while keeping its top edge attached to the screen.
    private func path(size: NSSize) -> CGPath {
        let left = (bounds.width - size.width) / 2
        let right = left + size.width
        let top: CGFloat = 0
        let bottom = top - size.height
        let topRadius = min(CalendarPanelLayout.panelTopCornerRadius, size.width / 4, size.height / 4)
        let bottomRadius = min(CalendarPanelLayout.panelBottomCornerRadius, (size.width - 2 * topRadius) / 2, size.height / 3)
        let k: CGFloat = 0.5522847498
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addCurve(to: CGPoint(x: right - topRadius, y: top - topRadius),
                      control1: CGPoint(x: right - topRadius * k, y: top),
                      control2: CGPoint(x: right - topRadius, y: top - topRadius * (1 - k)))
        path.addLine(to: CGPoint(x: right - topRadius, y: bottom + bottomRadius))
        path.addCurve(to: CGPoint(x: right - topRadius - bottomRadius, y: bottom),
                      control1: CGPoint(x: right - topRadius, y: bottom + bottomRadius * (1 - k)),
                      control2: CGPoint(x: right - topRadius - bottomRadius * (1 - k), y: bottom))
        path.addLine(to: CGPoint(x: left + topRadius + bottomRadius, y: bottom))
        path.addCurve(to: CGPoint(x: left + topRadius, y: bottom + bottomRadius),
                      control1: CGPoint(x: left + topRadius + bottomRadius * (1 - k), y: bottom),
                      control2: CGPoint(x: left + topRadius, y: bottom + bottomRadius * (1 - k)))
        path.addLine(to: CGPoint(x: left + topRadius, y: top - topRadius))
        path.addCurve(to: CGPoint(x: left, y: top),
                      control1: CGPoint(x: left + topRadius, y: top - topRadius * (1 - k)),
                      control2: CGPoint(x: left + topRadius * k, y: top))
        path.closeSubpath()
        return path
    }
}
