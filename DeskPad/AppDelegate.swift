import Carbon
import Cocoa
import ReSwift

enum AppDelegateAction: Action {
    case didFinishLaunching
}

enum UserDefaultsKey {
    static let keepOnTop = "keepOnTop"
    static let bringToFrontOnCursorEnter = "bringToFrontOnCursorEnter"
    static let windowSizes = "windowSizes"
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_: Notification) {
        UserDefaults.standard.register(defaults: [
            UserDefaultsKey.keepOnTop: false,
            UserDefaultsKey.bringToFrontOnCursorEnter: true,
        ])

        let viewController = ScreenViewController()
        window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.title = "DeskPad"
        window.makeKeyAndOrderFront(nil)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = maxDisplaySize
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenPrimary)
        applyKeepOnTop()

        NSApplication.shared.mainMenu = makeMainMenu()
        registerToggleCursorHotKey()

        store.dispatch(AppDelegateAction.didFinishLaunching)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Clicking the Dock icon always brings the window back, even if it got lost
        // (e.g. on the virtual display itself, or miniaturized).
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    // MARK: - Hot key

    /// Registers ⌃⌥⌘D as a global shortcut that moves the cursor onto the virtual display and back.
    private func registerToggleCursorHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            store.dispatch(MouseLocationAction.toggleCursorLocation)
            return OSStatus(noErr)
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4450_4144), id: 1) // "DPAD"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | optionKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "DeskPad")
        appMenu.addItem(NSMenuItem(
            title: "Hide DeskPad",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        let hideOthersMenuItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersMenuItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersMenuItem)
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        let newDisplayMenuItem = NSMenuItem(
            title: "New DeskPad Display",
            action: #selector(openNewInstance(_:)),
            keyEquivalent: "n"
        )
        newDisplayMenuItem.target = self
        appMenu.addItem(newDisplayMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit DeskPad",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        let fullScreenMenuItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenMenuItem.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(fullScreenMenuItem)
        windowMenu.addItem(.separator())
        // ⌃⌥⌘D is registered as a global hot key, so it's not set as key equivalent here.
        let toggleCursorMenuItem = NSMenuItem(
            title: "Move Cursor to/from DeskPad Display (⌃⌥⌘D)",
            action: #selector(toggleCursorLocation(_:)),
            keyEquivalent: ""
        )
        toggleCursorMenuItem.target = self
        windowMenu.addItem(toggleCursorMenuItem)
        let keepOnTopMenuItem = NSMenuItem(
            title: "Keep on Top",
            action: #selector(toggleKeepOnTop(_:)),
            keyEquivalent: "t"
        )
        keepOnTopMenuItem.keyEquivalentModifierMask = [.command, .option]
        keepOnTopMenuItem.target = self
        windowMenu.addItem(keepOnTopMenuItem)
        let bringToFrontMenuItem = NSMenuItem(
            title: "Bring to Front When Cursor Enters Display",
            action: #selector(toggleBringToFrontOnCursorEnter(_:)),
            keyEquivalent: ""
        )
        bringToFrontMenuItem.target = self
        windowMenu.addItem(bringToFrontMenuItem)
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }

    /// Each DeskPad instance provides one virtual display, so additional displays are separate instances.
    @objc private func openNewInstance(_: NSMenuItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    @objc private func toggleCursorLocation(_: NSMenuItem) {
        store.dispatch(MouseLocationAction.toggleCursorLocation)
    }

    @objc private func toggleKeepOnTop(_: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: UserDefaultsKey.keepOnTop), forKey: UserDefaultsKey.keepOnTop)
        applyKeepOnTop()
    }

    @objc private func toggleBringToFrontOnCursorEnter(_: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(
            !defaults.bool(forKey: UserDefaultsKey.bringToFrontOnCursorEnter),
            forKey: UserDefaultsKey.bringToFrontOnCursorEnter
        )
    }

    private func applyKeepOnTop() {
        window.level = UserDefaults.standard.bool(forKey: UserDefaultsKey.keepOnTop) ? .floating : .normal
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleKeepOnTop(_:)):
            menuItem.state = UserDefaults.standard.bool(forKey: UserDefaultsKey.keepOnTop) ? .on : .off
        case #selector(toggleBringToFrontOnCursorEnter(_:)):
            menuItem.state = UserDefaults.standard.bool(forKey: UserDefaultsKey.bringToFrontOnCursorEnter) ? .on : .off
        default:
            break
        }
        return true
    }
}
