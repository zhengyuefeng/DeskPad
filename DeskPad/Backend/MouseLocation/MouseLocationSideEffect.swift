import Foundation
import ReSwift

private var timer: Timer?
private var cursorLocationOutsideScreen: CGPoint?

enum MouseLocationAction: Action {
    case located(isWithinScreen: Bool)
    case requestMove(toPoint: NSPoint)
    case toggleCursorLocation
}

func mouseLocationSideEffect() -> SideEffect {
    return { action, dispatch, getState in
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                let mouseLocation = NSEvent.mouseLocation
                let screens = NSScreen.screens
                let screenContainingMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
                let isWithinScreen = screenContainingMouse?.displayID == getState()?.screenConfigurationState.displayID
                dispatch(MouseLocationAction.located(isWithinScreen: isWithinScreen))
            }
        }
        if case .toggleCursorLocation? = action as? MouseLocationAction {
            if let displayID = getState()?.screenConfigurationState.displayID {
                toggleCursorLocation(displayID: displayID)
            }
            return
        }
        switch action {
        case let MouseLocationAction.requestMove(point):
            guard let displayID = getState()?.screenConfigurationState.displayID else {
                return
            }
            CGDisplayMoveCursorToPoint(displayID, point)
        default:
            return
        }
    }
}

/// Moves the cursor onto the center of the virtual display, or back to where it was before.
private func toggleCursorLocation(displayID: CGDirectDisplayID) {
    // CoreGraphics uses a top-left origin relative to the primary screen, AppKit a bottom-left one.
    let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    let mouseLocation = NSEvent.mouseLocation
    let currentLocation = CGPoint(x: mouseLocation.x, y: primaryScreenHeight - mouseLocation.y)
    let displayBounds = CGDisplayBounds(displayID)
    if displayBounds.contains(currentLocation) {
        let fallbackScreen = NSScreen.screens.first { $0.displayID != displayID }
        guard let target = cursorLocationOutsideScreen ?? fallbackScreen.map({
            CGPoint(x: $0.frame.midX, y: primaryScreenHeight - $0.frame.midY)
        }) else {
            return
        }
        CGWarpMouseCursorPosition(target)
    } else {
        cursorLocationOutsideScreen = currentLocation
        CGWarpMouseCursorPosition(CGPoint(x: displayBounds.midX, y: displayBounds.midY))
    }
    CGAssociateMouseAndMouseCursorPosition(1)
}
