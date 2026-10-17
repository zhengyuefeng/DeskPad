import Cocoa

/// Safe area mode is meant for a physical screen that is damaged along one or more of its edges:
/// the virtual display is sized to the intact part of that screen, becomes the main display and is
/// shown in a borderless window covering exactly the intact part. The cursor is kept on the virtual
/// display, so nothing is ever shown on or reachable through the damaged part.
enum SafeArea {
    static let settingsDidChangeNotification = Notification.Name("SafeAreaSettingsDidChange")

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKey.safeAreaEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.safeAreaEnabled) }
    }

    /// Insets (in points) of the damaged regions along the edges of the physical screen.
    static var insets: NSEdgeInsets {
        get {
            let defaults = UserDefaults.standard
            return NSEdgeInsets(
                top: defaults.double(forKey: UserDefaultsKey.safeAreaInsetTop),
                left: defaults.double(forKey: UserDefaultsKey.safeAreaInsetLeft),
                bottom: defaults.double(forKey: UserDefaultsKey.safeAreaInsetBottom),
                right: defaults.double(forKey: UserDefaultsKey.safeAreaInsetRight)
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Double(newValue.top), forKey: UserDefaultsKey.safeAreaInsetTop)
            defaults.set(Double(newValue.left), forKey: UserDefaultsKey.safeAreaInsetLeft)
            defaults.set(Double(newValue.bottom), forKey: UserDefaultsKey.safeAreaInsetBottom)
            defaults.set(Double(newValue.right), forKey: UserDefaultsKey.safeAreaInsetRight)
        }
    }

    /// The damaged physical screen: the built-in display if there is one, otherwise the first other screen.
    static func physicalScreen(excluding virtualDisplayID: CGDirectDisplayID) -> NSScreen? {
        let screens = NSScreen.screens.filter { $0.displayID != virtualDisplayID }
        return screens.first { CGDisplayIsBuiltin($0.displayID) != 0 } ?? screens.first
    }

    /// The intact part of the given screen, in AppKit (bottom-left origin) coordinates.
    static func intactFrame(of screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let insets = self.insets
        return NSRect(
            x: frame.minX + insets.left,
            y: frame.minY + insets.bottom,
            width: max(frame.width - insets.left - insets.right, 0),
            height: max(frame.height - insets.top - insets.bottom, 0)
        )
    }

    /// The resolution (in points) the virtual display needs to fill the intact part of the screen.
    static func resolution(for screen: NSScreen) -> CGSize {
        let frame = intactFrame(of: screen)
        return CGSize(width: floor(frame.width), height: floor(frame.height))
    }

    /// Makes the virtual display the main display (so it gets the menu bar, Dock and new windows) by
    /// moving it to the origin and placing all other displays to its right. Only lasts while DeskPad runs.
    static func makeMainDisplay(_ virtualDisplayID: CGDirectDisplayID) {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)
        let otherDisplayIDs = displayIDs.prefix(Int(displayCount)).filter {
            $0 != virtualDisplayID && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay
        }
        let otherBounds = otherDisplayIDs.map(CGDisplayBounds)
        guard let minX = otherBounds.map(\.minX).min(), let minY = otherBounds.map(\.minY).min() else {
            return
        }
        let virtualBounds = CGDisplayBounds(virtualDisplayID)

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            return
        }
        CGConfigureDisplayOrigin(config, virtualDisplayID, 0, 0)
        for (displayID, bounds) in zip(otherDisplayIDs, otherBounds) {
            CGConfigureDisplayOrigin(
                config,
                displayID,
                Int32(virtualBounds.width + bounds.minX - minX),
                Int32(bounds.minY - minY)
            )
        }
        CGCompleteDisplayConfiguration(config, .forAppOnly)
    }

    /// Undoes `makeMainDisplay`.
    static func restoreDisplayArrangement() {
        CGRestorePermanentDisplayConfiguration()
    }
}

/// Keeps the cursor within the bounds of a display.
final class CursorConfinement {
    private let displayID: CGDirectDisplayID
    private var monitors: [Any] = []

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.confineCursor()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.confineCursor()
            return event
        }) {
            monitors.append(monitor)
        }
        confineCursor()
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func confineCursor() {
        // CoreGraphics coordinates (top-left origin), same as CGDisplayBounds.
        guard let location = CGEvent(source: nil)?.location else {
            return
        }
        let bounds = CGDisplayBounds(displayID)
        guard !bounds.isEmpty, !bounds.contains(location) else {
            return
        }
        let confinedLocation = CGPoint(
            x: min(max(location.x, bounds.minX), bounds.maxX - 1),
            y: min(max(location.y, bounds.minY), bounds.maxY - 1)
        )
        CGWarpMouseCursorPosition(confinedLocation)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
