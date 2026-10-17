<h3 align="center">
  <a href="https://github.com/Stengo/DeskPad/blob/main/DeskPad/Assets.xcassets/AppIcon.appiconset/Icon-256.png">
  <img src="https://github.com/Stengo/DeskPad/blob/main/DeskPad/Assets.xcassets/AppIcon.appiconset/Icon-256.png?raw=true" alt="DeskPad Icon" width="128">
  </a>
</h3>

# DeskPad
A virtual monitor for screen sharing

<h3 align="center">
  <a href="https://github.com/Stengo/DeskPad/blob/main/screenshot.jpg">
  <img src="https://github.com/Stengo/DeskPad/blob/main/screenshot.jpg?raw=true" alt="DeskPad Screenshot">
  </a>
</h3>

Certain workflows require sharing the entire screen (usually due to switching through multiple applications), but if the presenter has a much larger display than the audience it can be hard to see what is happening.

DeskPad creates a virtual display that is mirrored within its application window so that you can create a dedicated, easily shareable workspace.

# Installation
You can either download the [latest release binary](https://github.com/Stengo/DeskPad/releases) or install via [Homebrew](https://brew.sh) by calling `brew install --cask deskpad`.

# Usage
DeskPad behaves like any other display. Launching the app is equivalent to plugging in a monitor, so macOS will take care of properly arranging your windows to their previous configuration.

You can change the display resolution through the system preferences and the application window will adjust accordingly.

Whenever you move your mouse cursor to the virtual display, DeskPad will highlight its title bar in blue and move the application window to the front to let you know where you are.
This can be turned off via **Window** → **Bring to Front When Cursor Enters Display**.

The **Window** menu also offers:

- **Keep on Top** (⌥⌘T) to keep the DeskPad window above all other windows
- **Enter Full Screen** (⌃⌘F)
- **Move Cursor to/from DeskPad Display**, also available system-wide via ⌃⌥⌘D

The window size and position are remembered per resolution. If the DeskPad window ever ends up on the virtual display itself, it moves back to a physical screen; clicking the Dock icon also brings it back to the front.

To get additional virtual displays, choose **DeskPad** → **New DeskPad Display** (⌘N), which launches another DeskPad instance with its own display.

## Safe area mode (damaged screens)

If part of your screen is damaged along one or more edges, choose **Window** → **Configure Safe Area…** and enter how many points along each edge are damaged. DeskPad then sizes its virtual display to the intact part of the built-in screen (or the first physical screen), makes it the main display (menu bar, Dock and new windows go there), shows it in a borderless window that exactly covers the intact part, and keeps the cursor out of the damaged part. Quitting DeskPad or turning **Window** → **Safe Area Mode** off restores the normal layout. Hold Option while launching DeskPad to start with safe area mode turned off.

DeskPad can also be launched with a specific resolution from the terminal:

```sh
open -a DeskPad --args --width 1280 --height 800
```

<h3 align="center">
  <a href="https://github.com/Stengo/DeskPad/blob/main/demonstration.gif">
  <img src="https://github.com/Stengo/DeskPad/blob/main/demonstration.gif?raw=true" alt="DeskPad Demonstration">
  </a>
</h3>

# Troubleshooting
DeskPad may need screen recording permissions to display properly. Follow these steps:

1. **Open System Settings** → **Privacy & Security** → **Screen Recording**
2. **Enable DeskPad** by checking the box next to it
3. **If DeskPad appears but isn't working:**
   - Uncheck the DeskPad option
   - Check it again to re-enable
4. **Restart DeskPad** for changes to take effect
