import AppKit
import Combine
import QuartzCore

final class NotchWindow: NSPanel {
    static let maxExpandedWidth: CGFloat = 520
    static let maxExpandedHeight: CGFloat = 600

    private static let expandedPadding: CGFloat = 8
    private static let collapsedHitHeight: CGFloat = 32

    static func islandTopOffset(for _: NSScreen) -> CGFloat { 0 }

    /// True when the island sits in the built-in display’s top-center notch band (camera housing occludes content).
    func isObscuredByPhysicalNotch() -> Bool {
        guard let screen = self.screen else { return false }
        if #available(macOS 14.0, *) {
            guard screen.safeAreaInsets.top > 0 else { return false }
        } else {
            return false
        }
        let sf = screen.frame
        let wf = frame
        let topAligned = abs(wf.maxY - sf.maxY) < 4
        let inCenterBand = abs(wf.midX - sf.midX) < sf.width * 0.22
        return topAligned && inCenterBand
    }

    var customX: CGFloat?
    private(set) var isDragging = false
    private var dragTracking = false
    private var dragStartWindowX: CGFloat = 0
    private var dragStartMouseX: CGFloat = 0

    init() {
        let screen = Self.bestScreen()
        let width: CGFloat = 220
        let height: CGFloat = 50
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        let y = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen) - height

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        applySpaceBehavior()

        contentView = FlippedView(frame: .zero)
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = .clear

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    func applySpaceBehavior() {
        let allSpaces = UserDefaults.standard.bool(forKey: "showOnAllSpaces")
        if allSpaces {
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            collectionBehavior = [.fullScreenAuxiliary, .stationary]
        }
    }

    @objc private func activeSpaceDidChange(_ note: Notification) {
        let hideInFullscreen = UserDefaults.standard.bool(forKey: "hideInFullscreen")
        guard hideInFullscreen else {
            if !isVisible { orderFrontRegardless() }
            return
        }
        if let screen = NSScreen.main, isScreenInFullscreen(screen) {
            orderOut(nil)
        } else {
            orderFrontRegardless()
        }
    }

    private func isScreenInFullscreen(_ screen: NSScreen) -> Bool {
        for window in NSApplication.shared.windows where window !== self {
            if window.styleMask.contains(.fullScreen) && window.screen == screen {
                return true
            }
        }
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
            guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
                return false
            }
            for info in list {
                if let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                   pid == frontApp.processIdentifier,
                   let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                   let w = bounds["Width"], let h = bounds["Height"],
                   w >= screen.frame.width && h >= screen.frame.height {
                    return true
                }
            }
        }
        return false
    }

    func resizeToFit(contentWidth: CGFloat, contentHeight: CGFloat, display: Bool = true) {
        let screen = Self.bestScreen()
        let padding = Self.padding(forContentHeight: contentHeight)
        let w = contentWidth + padding * 2
        let h = contentHeight + padding
        let x: CGFloat
        if let cx = customX {
            x = max(screen.frame.origin.x,
                    min(cx - w / 2, screen.frame.origin.x + screen.frame.width - w))
        } else {
            x = screen.frame.origin.x + (screen.frame.width - w) / 2
        }
        let screenTop = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen)
        let yComputed = screenTop - h
        let rect = NSRect(x: x, y: yComputed, width: w, height: h)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        setFrameDirect(rect, display: display)
        NSAnimationContext.endGrouping()
    }

    func resizeToFitCollapse(contentWidth: CGFloat, contentHeight: CGFloat) {
        let screen = Self.bestScreen()
        let targetW = contentWidth
        let targetH = contentHeight
        let targetX: CGFloat
        if let cx = customX {
            targetX = max(screen.frame.origin.x,
                          min(cx - targetW / 2, screen.frame.origin.x + screen.frame.width - targetW))
        } else {
            targetX = screen.frame.origin.x + (screen.frame.width - targetW) / 2
        }
        let screenTop = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen)
        let targetY = screenTop - targetH

        isDragging = false
        dragTracking = false

        let target = NSRect(x: targetX, y: targetY, width: targetW, height: targetH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        setFrameDirect(target, display: true)
        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }

    static func bestScreen() -> NSScreen {
        if let builtIn = NSScreen.screens.first(where: {
            $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")]
                as? CGDirectDisplayID == CGMainDisplayID()
        }) {
            return builtIn
        }
        return NSScreen.screens[0]
    }

    @objc private func screenDidChange(_ note: Notification) {
        let screen = Self.bestScreen()
        let x: CGFloat
        if let cx = customX {
            x = max(screen.frame.origin.x,
                    min(cx - frame.width / 2, screen.frame.origin.x + screen.frame.width - frame.width))
        } else {
            x = screen.frame.origin.x + (screen.frame.width - frame.width) / 2
        }
        let screenTop = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen)
        let y = screenTop - frame.height
        setFrameDirect(NSRect(x: x, y: y, width: frame.width, height: frame.height), display: true)
    }

    private static func padding(forContentHeight contentHeight: CGFloat) -> CGFloat {
        contentHeight <= collapsedHitHeight + 0.5 ? 0 : expandedPadding
    }

    // MARK: - Horizontal drag via sendEvent

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStartMouseX = NSEvent.mouseLocation.x
            dragStartWindowX = frame.origin.x
            dragTracking = true
            isDragging = false
            super.sendEvent(event)

        case .leftMouseDragged where dragTracking:
            let currentX = NSEvent.mouseLocation.x
            let dx = currentX - dragStartMouseX
            if !isDragging && abs(dx) > 4 {
                isDragging = true
            }
            if isDragging {
                let screen = Self.bestScreen()
                let newX = max(screen.frame.origin.x,
                               min(dragStartWindowX + dx,
                                   screen.frame.origin.x + screen.frame.width - frame.width))
                let topY = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen) - frame.height
                setFrameDirect(NSRect(x: newX, y: topY, width: frame.width, height: frame.height))
            } else {
                super.sendEvent(event)
            }

        case .leftMouseUp where dragTracking:
            dragTracking = false
            if isDragging {
                customX = frame.origin.x + frame.width / 2
                isDragging = false
            } else {
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }

    func setFrameDirect(_ rect: NSRect, display: Bool = true) {
        super.setFrame(rect, display: display)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let screen = Self.bestScreen()
        let topY = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen) - frameRect.height
        let x: CGFloat
        if isDragging || dragTracking {
            x = frame.origin.x
        } else if let cx = customX {
            x = max(screen.frame.origin.x,
                    min(cx - frameRect.width / 2,
                        screen.frame.origin.x + screen.frame.width - frameRect.width))
        } else {
            x = screen.frame.origin.x + (screen.frame.width - frameRect.width) / 2
        }
        let pinned = NSRect(x: x, y: topY, width: frameRect.width, height: frameRect.height)
        super.setFrame(pinned, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        let screen = Self.bestScreen()
        let topY = screen.frame.origin.y + screen.frame.height - Self.islandTopOffset(for: screen) - frameRect.height
        let x: CGFloat
        if isDragging || dragTracking {
            x = frame.origin.x
        } else if let cx = customX {
            x = max(screen.frame.origin.x,
                    min(cx - frameRect.width / 2,
                        screen.frame.origin.x + screen.frame.width - frameRect.width))
        } else {
            x = screen.frame.origin.x + (screen.frame.width - frameRect.width) / 2
        }
        let pinned = NSRect(x: x, y: topY, width: frameRect.width, height: frameRect.height)
        super.setFrame(pinned, display: displayFlag, animate: animateFlag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
