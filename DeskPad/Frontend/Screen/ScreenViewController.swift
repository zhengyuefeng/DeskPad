import Cocoa
import ReSwift

enum ScreenViewAction: Action {
    case setDisplayID(CGDirectDisplayID)
}

let maxDisplaySize = CGSize(width: 7680, height: 4800)

class ScreenViewController: SubscriberViewController<ScreenViewData>, NSWindowDelegate {
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickOnScreen)))
    }

    private var display: CGVirtualDisplay!
    private var stream: CGDisplayStream?
    private var isWindowHighlighted = false
    private var previousResolution: CGSize?
    private var previousScaleFactor: CGFloat?

    override func viewDidLoad() {
        super.viewDidLoad()

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "DeskPad Display"
        // HiDPI modes need twice the pixels of the mode itself, so leave enough room
        // for e.g. 1920x1200 and 2560x1600 to be offered in HiDPI.
        descriptor.maxPixelsWide = UInt32(maxDisplaySize.width)
        descriptor.maxPixelsHigh = UInt32(maxDisplaySize.height)
        descriptor.sizeInMillimeters = CGSize(width: 1600, height: 1000)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)
        store.dispatch(ScreenViewAction.setDisplayID(display.displayID))
        self.display = display

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [
            // 32:9
            CGVirtualDisplayMode(width: 5120, height: 1440, refreshRate: 60),
            // 21:9 (239:100, 12:5)
            CGVirtualDisplayMode(width: 5120, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 3440, height: 1440, refreshRate: 60),
            // 16:9
            CGVirtualDisplayMode(width: 6016, height: 3384, refreshRate: 60),
            CGVirtualDisplayMode(width: 5120, height: 2880, refreshRate: 60),
            CGVirtualDisplayMode(width: 4096, height: 2304, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 2160, refreshRate: 60),
            CGVirtualDisplayMode(width: 2560, height: 1440, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60),
            CGVirtualDisplayMode(width: 1600, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1366, height: 768, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 720, refreshRate: 60),
            // 16:10
            CGVirtualDisplayMode(width: 5120, height: 3200, refreshRate: 60),
            CGVirtualDisplayMode(width: 3840, height: 2400, refreshRate: 60),
            CGVirtualDisplayMode(width: 2880, height: 1800, refreshRate: 60),
            CGVirtualDisplayMode(width: 2560, height: 1600, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1200, refreshRate: 60),
            CGVirtualDisplayMode(width: 1680, height: 1050, refreshRate: 60),
            CGVirtualDisplayMode(width: 1440, height: 900, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 800, refreshRate: 60),
        ]
        display.apply(settings)
    }

    override func update(with viewData: ScreenViewData) {
        if viewData.isWindowHighlighted != isWindowHighlighted {
            isWindowHighlighted = viewData.isWindowHighlighted
            view.window?.backgroundColor = isWindowHighlighted
                ? NSColor(named: "TitleBarActive")
                : NSColor(named: "TitleBarInactive")
            if isWindowHighlighted, UserDefaults.standard.bool(forKey: UserDefaultsKey.bringToFrontOnCursorEnter) {
                view.window?.orderFrontRegardless()
            }
        }

        if
            viewData.resolution != .zero,
            viewData.resolution != previousResolution
            || viewData.scaleFactor != previousScaleFactor
        {
            previousResolution = viewData.resolution
            previousScaleFactor = viewData.scaleFactor
            stream = nil
            if let window = view.window {
                window.contentAspectRatio = viewData.resolution
                if !window.styleMask.contains(.fullScreen) {
                    if let savedFrame = savedWindowFrame(for: viewData.resolution) {
                        window.setFrame(savedFrame, display: true)
                    } else {
                        window.setContentSize(viewData.resolution)
                        window.center()
                    }
                }
            }
            let stream = CGDisplayStream(
                dispatchQueueDisplay: display.displayID,
                outputWidth: Int(viewData.resolution.width * viewData.scaleFactor),
                outputHeight: Int(viewData.resolution.height * viewData.scaleFactor),
                pixelFormat: 1_111_970_369,
                properties: [
                    CGDisplayStream.showCursor: true,
                ] as CFDictionary,
                queue: .main,
                handler: { [weak self] _, _, frameSurface, _ in
                    if let surface = frameSurface {
                        self?.view.layer?.contents = surface
                    }
                }
            )
            self.stream = stream
            stream?.start()
        }
    }

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        let snappingOffset: CGFloat = 30
        let contentSize = window.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard
            let screenResolution = previousResolution,
            abs(contentSize.width - screenResolution.width) < snappingOffset
        else {
            return frameSize
        }
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: screenResolution)).size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame(of: notification.object as? NSWindow)
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame(of: notification.object as? NSWindow)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            !window.styleMask.contains(.fullScreen),
            window.screen?.displayID == display.displayID,
            let targetScreen = NSScreen.screens.first(where: { $0.displayID != display.displayID })
        else {
            return
        }
        // The DeskPad window ended up on its own virtual display, which makes it unreachable.
        // Move it back onto a physical screen.
        let visibleFrame = targetScreen.visibleFrame
        var frame = window.frame
        if frame.width > visibleFrame.width || frame.height > visibleFrame.height {
            let scale = min(visibleFrame.width / frame.width, visibleFrame.height / frame.height)
            frame.size = CGSize(width: frame.width * scale, height: frame.height * scale)
        }
        frame.origin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: true)
    }

    private func windowSizesKey(for resolution: CGSize) -> String {
        return "\(Int(resolution.width))x\(Int(resolution.height))"
    }

    private func savedWindowFrame(for resolution: CGSize) -> NSRect? {
        guard
            let frames = UserDefaults.standard.dictionary(forKey: UserDefaultsKey.windowSizes) as? [String: String],
            let frameString = frames[windowSizesKey(for: resolution)]
        else {
            return nil
        }
        let frame = NSRectFromString(frameString)
        let isOnPhysicalScreen = NSScreen.screens.contains {
            $0.displayID != display.displayID && $0.visibleFrame.intersects(frame)
        }
        return frame.isEmpty || !isOnPhysicalScreen ? nil : frame
    }

    private func saveWindowFrame(of window: NSWindow?) {
        guard
            let window = window,
            let resolution = previousResolution,
            !window.styleMask.contains(.fullScreen),
            window.screen?.displayID != display.displayID
        else {
            return
        }
        var frames = UserDefaults.standard.dictionary(forKey: UserDefaultsKey.windowSizes) as? [String: String] ?? [:]
        frames[windowSizesKey(for: resolution)] = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frames, forKey: UserDefaultsKey.windowSizes)
    }

    @objc private func didClickOnScreen(_ gestureRecognizer: NSGestureRecognizer) {
        guard let screenResolution = previousResolution else {
            return
        }
        // The stream is drawn aspect-fit, so account for letterboxing (e.g. in full screen).
        let scale = min(view.bounds.width / screenResolution.width, view.bounds.height / screenResolution.height)
        let contentSize = CGSize(width: screenResolution.width * scale, height: screenResolution.height * scale)
        let contentOrigin = CGPoint(
            x: (view.bounds.width - contentSize.width) / 2,
            y: (view.bounds.height - contentSize.height) / 2
        )
        let clickedPoint = gestureRecognizer.location(in: view)
        let onScreenPoint = NSPoint(
            x: min(max((clickedPoint.x - contentOrigin.x) / scale, 0), screenResolution.width - 1),
            y: min(max((contentOrigin.y + contentSize.height - clickedPoint.y) / scale, 0), screenResolution.height - 1)
        )
        store.dispatch(MouseLocationAction.requestMove(toPoint: onScreenPoint))
    }
}
