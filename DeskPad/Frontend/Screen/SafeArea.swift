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

    /// The frame of the given screen, in AppKit (bottom-left origin) coordinates.
    static func currentFrame(of screen: NSScreen) -> NSRect {
        // Derive the frame from the current display bounds, as `NSScreen.frame` can lag behind
        // right after the display arrangement changed.
        let bounds = CGDisplayBounds(screen.displayID)
        let primaryDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return bounds.isEmpty ? screen.frame : NSRect(
            x: bounds.minX,
            y: primaryDisplayHeight - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// The intact part of the given screen, in AppKit (bottom-left origin) coordinates.
    static func intactFrame(of screen: NSScreen) -> NSRect {
        let frame = currentFrame(of: screen)
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

    /// Switches the virtual display to `mode` and makes it the main display (so it gets the menu bar, Dock and
    /// new windows) by moving it to the origin and placing all other displays to its right. Mirroring of the
    /// virtual display is turned off, as a physical screen mirroring it would show the DeskPad window within
    /// itself. All of this happens in one configuration, which only lasts while DeskPad runs.
    static func makeMainDisplay(_ virtualDisplayID: CGDirectDisplayID, mode: CGDisplayMode?) {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)
        let otherDisplayIDs = displayIDs.prefix(Int(displayCount)).filter { $0 != virtualDisplayID }
        // Only mirroring involving the virtual display is turned off; other mirror sets are left alone (and
        // move along with the display they mirror).
        let virtualMirrorPartnerIDs = otherDisplayIDs.filter {
            CGDisplayMirrorsDisplay($0) == virtualDisplayID || CGDisplayMirrorsDisplay(virtualDisplayID) == $0
        }
        let extendedDisplayIDs = otherDisplayIDs.filter {
            !virtualMirrorPartnerIDs.contains($0) && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay
        }
        // Displays that mirrored the virtual display have its bounds, so they are placed separately.
        let mirroringDisplayIDs = virtualMirrorPartnerIDs
        let extendedBounds = extendedDisplayIDs.map(CGDisplayBounds)
        let minX = extendedBounds.map(\.minX).min() ?? 0
        let minY = extendedBounds.map(\.minY).min() ?? 0
        // Use the size the virtual display is about to have, not its current one.
        let virtualWidth = mode.map { CGFloat($0.width) } ?? CGDisplayBounds(virtualDisplayID).width

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            return
        }
        for displayID in [virtualDisplayID] + virtualMirrorPartnerIDs where CGDisplayIsInMirrorSet(displayID) != 0 {
            CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        }
        if let mode = mode {
            CGConfigureDisplayWithDisplayMode(config, virtualDisplayID, mode, nil)
        }
        CGConfigureDisplayOrigin(config, virtualDisplayID, 0, 0)
        var maxX = virtualWidth
        for (displayID, bounds) in zip(extendedDisplayIDs, extendedBounds) {
            let x = virtualWidth + bounds.minX - minX
            CGConfigureDisplayOrigin(config, displayID, Int32(x), Int32(bounds.minY - minY))
            maxX = max(maxX, x + bounds.width)
        }
        for displayID in mirroringDisplayIDs {
            CGConfigureDisplayOrigin(config, displayID, Int32(maxX), 0)
            maxX += CGDisplayBounds(displayID).width
        }
        CGCompleteDisplayConfiguration(config, .forAppOnly)
    }

    /// Safe area mode covers the physical screen with the captured virtual display, so without screen recording
    /// access the screen would turn completely black. Requests the access and explains it if it's missing.
    static func ensureScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen recording access needed"
            alert.informativeText = "Safe area mode shows the virtual display in place of your screen, which requires "
                + "DeskPad to be allowed in System Settings › Privacy & Security › Screen & System Audio Recording. "
                + "Allow it there, quit and reopen DeskPad, then turn safe area mode on again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        return false
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

// MARK: - Selecting the intact area

extension SafeArea {
    private static var selectionWindow: SafeAreaSelectionWindow?

    /// Shows a full-screen overlay on `screen` in which the intact area can be selected by dragging.
    /// Calls `completion` with the resulting insets, or `nil` if the selection was cancelled.
    static func selectIntactArea(on screen: NSScreen, completion: @escaping (NSEdgeInsets?) -> Void) {
        let screenSize = screen.frame.size
        let insets = self.insets
        let initialSelection = NSRect(
            x: insets.left,
            y: insets.bottom,
            width: screenSize.width - insets.left - insets.right,
            height: screenSize.height - insets.top - insets.bottom
        )
        let window = SafeAreaSelectionWindow(screen: screen, initialSelection: initialSelection) { selection in
            selectionWindow?.orderOut(nil)
            selectionWindow = nil
            completion(selection.map {
                NSEdgeInsets(
                    top: (screenSize.height - $0.maxY).rounded(),
                    left: $0.minX.rounded(),
                    bottom: $0.minY.rounded(),
                    right: (screenSize.width - $0.maxX).rounded()
                )
            })
        }
        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class SafeAreaSelectionWindow: NSWindow {
    init(screen: NSScreen, initialSelection: NSRect, completion: @escaping (NSRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
        let selectionView = SafeAreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.selection = initialSelection.intersection(selectionView.bounds).isEmpty
            ? selectionView.bounds.insetBy(dx: 100, dy: 100)
            : initialSelection.intersection(selectionView.bounds)
        selectionView.onFinish = completion
        contentView = selectionView
        initialFirstResponder = selectionView
    }

    override var canBecomeKey: Bool {
        return true
    }
}

private final class SafeAreaSelectionView: NSView {
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let bottom = Edges(rawValue: 1 << 2)
        static let top = Edges(rawValue: 1 << 3)
    }

    private enum DragOperation {
        case create(origin: NSPoint)
        case resize(Edges)
        case move(offset: NSSize)
    }

    private static let minimumSize = CGSize(width: 200, height: 150)
    private static let edgeTolerance: CGFloat = 12

    var selection: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    var onFinish: ((NSRect?) -> Void)?

    private var dragOperation: DragOperation?

    /// The edges the arrow keys move. Along an axis without an active edge, they move the whole selection.
    private var activeEdges: Edges = [] {
        didSet { needsDisplay = true }
    }

    /// The order in which Tab cycles through the edges.
    private static let edgeCycle: [Edges] = [.left, .top, .right, .bottom, []]

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_: NSRect) {
        let dimmedArea = NSBezierPath(rect: bounds)
        dimmedArea.append(NSBezierPath(rect: selection))
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.6).setFill()
        dimmedArea.fill()

        let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        NSColor.systemOrange.setStroke()
        for (edge, from, to) in [
            (Edges.left, NSPoint(x: selection.minX, y: selection.minY), NSPoint(x: selection.minX, y: selection.maxY)),
            (Edges.right, NSPoint(x: selection.maxX, y: selection.minY), NSPoint(x: selection.maxX, y: selection.maxY)),
            (Edges.bottom, NSPoint(x: selection.minX, y: selection.minY), NSPoint(x: selection.maxX, y: selection.minY)),
            (Edges.top, NSPoint(x: selection.minX, y: selection.maxY), NSPoint(x: selection.maxX, y: selection.maxY)),
        ] where activeEdges.contains(edge) {
            let line = NSBezierPath()
            line.move(to: from)
            line.line(to: to)
            line.lineWidth = 6
            line.stroke()
        }

        let text = """
        Drag to select the intact part of the screen, drag its edges to adjust it.
        Arrow keys fine-tune the highlighted edge (or move the selection), Shift for 10 points, Tab switches edges.
        Press Return to confirm or Esc to cancel.

        \(Int(selection.width.rounded())) × \(Int(selection.height.rounded())) points
        """
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: {
                let shadow = NSShadow()
                shadow.shadowColor = .black
                shadow.shadowBlurRadius = 4
                return shadow
            }(),
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.boundingRect(
            with: CGSize(width: max(selection.width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).size
        attributedText.draw(with: NSRect(
            x: selection.midX - textSize.width / 2,
            y: selection.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        ), options: [.usesLineFragmentOrigin])
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selection.contains(point) {
            onFinish?(selection)
            return
        }
        let edges = self.edges(near: point)
        activeEdges = edges
        if !edges.isEmpty {
            dragOperation = .resize(edges)
        } else if selection.contains(point) {
            dragOperation = .move(offset: NSSize(width: point.x - selection.minX, height: point.y - selection.minY))
        } else {
            dragOperation = .create(origin: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        switch dragOperation {
        case let .create(origin):
            selection = NSRect(
                x: min(origin.x, point.x),
                y: min(origin.y, point.y),
                width: abs(point.x - origin.x),
                height: abs(point.y - origin.y)
            )
        case let .resize(edges):
            resize(edges, to: point)
        case let .move(offset):
            move(to: NSPoint(x: point.x - offset.width, y: point.y - offset.height))
        case nil:
            break
        }
    }

    override func mouseUp(with _: NSEvent) {
        if case .create = dragOperation,
           selection.width < Self.minimumSize.width || selection.height < Self.minimumSize.height
        {
            // Too small to be meant as a selection, e.g. a click: grow it to the minimum size.
            selection = NSRect(
                x: selection.minX,
                y: selection.minY,
                width: max(selection.width, Self.minimumSize.width),
                height: max(selection.height, Self.minimumSize.height)
            ).intersection(bounds)
        }
        dragOperation = nil
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, Enter
            onFinish?(selection)
        case 53: // Escape
            onFinish?(nil)
        case 48: // Tab
            let index = Self.edgeCycle.firstIndex(of: activeEdges) ?? Self.edgeCycle.count - 1
            activeEdges = Self.edgeCycle[(index + 1) % Self.edgeCycle.count]
        case 123, 124, 125, 126: // Left, Right, Down, Up
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
            nudge(dx: dx, dy: dy)
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_: Any?) {
        onFinish?(nil)
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        let horizontalEdges = activeEdges.intersection([.left, .right])
        let verticalEdges = activeEdges.intersection([.bottom, .top])
        if dx != 0 {
            if horizontalEdges.isEmpty {
                move(to: NSPoint(x: selection.minX + dx, y: selection.minY))
            } else {
                if horizontalEdges.contains(.left) { resize(.left, to: NSPoint(x: selection.minX + dx, y: 0)) }
                if horizontalEdges.contains(.right) { resize(.right, to: NSPoint(x: selection.maxX + dx, y: 0)) }
            }
        }
        if dy != 0 {
            if verticalEdges.isEmpty {
                move(to: NSPoint(x: selection.minX, y: selection.minY + dy))
            } else {
                if verticalEdges.contains(.bottom) { resize(.bottom, to: NSPoint(x: 0, y: selection.minY + dy)) }
                if verticalEdges.contains(.top) { resize(.top, to: NSPoint(x: 0, y: selection.maxY + dy)) }
            }
        }
    }

    /// Moves the given edges of the selection to `point`, keeping the minimum size and staying on screen.
    private func resize(_ edges: Edges, to point: NSPoint) {
        let point = clamped(point)
        var minX = selection.minX, maxX = selection.maxX, minY = selection.minY, maxY = selection.maxY
        let minimumSize = Self.minimumSize
        if edges.contains(.left) { minX = min(point.x, maxX - minimumSize.width) }
        if edges.contains(.right) { maxX = max(point.x, minX + minimumSize.width) }
        if edges.contains(.bottom) { minY = min(point.y, maxY - minimumSize.height) }
        if edges.contains(.top) { maxY = max(point.y, minY + minimumSize.height) }
        selection = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
    }

    /// Moves the selection's origin to `origin`, keeping it on screen.
    private func move(to origin: NSPoint) {
        var frame = selection
        frame.origin = NSPoint(
            x: min(max(origin.x, bounds.minX), bounds.maxX - frame.width),
            y: min(max(origin.y, bounds.minY), bounds.maxY - frame.height)
        )
        selection = frame
    }

    private func edges(near point: NSPoint) -> Edges {
        let tolerance = Self.edgeTolerance
        guard selection.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else {
            return []
        }
        var edges: Edges = []
        if abs(point.x - selection.minX) < tolerance { edges.insert(.left) }
        if abs(point.x - selection.maxX) < tolerance { edges.insert(.right) }
        if abs(point.y - selection.minY) < tolerance { edges.insert(.bottom) }
        if abs(point.y - selection.maxY) < tolerance { edges.insert(.top) }
        return edges
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        return NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
