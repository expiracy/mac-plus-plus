# MacsPane

MacsPane is one of the two pages of [mac++](../README.md)'s menu-bar dropdown. Installing, building and
releasing are in the README; this page is what MacsPane does.

Drag a window to the notch, hold it there, and drop it into a layout.

MacsPane is a menu-bar window manager for macOS. When you drag a window by its title bar to the top of
the screen and rest it on the notch, the notch opens into a row of layouts: halves, two thirds, fill,
desk and quarters to start with, and any you draw yourself. Let go on a box and the window fills it. Everything else (drawing and
applying presets, drawing layouts and settings) starts from MacsPane's page of the mac++ menu.

## Using it

- **Snap a window.** Drag it by its title bar onto the notch and pause. Aim at a box in one of the
  layouts and let go. Letting go anywhere else leaves the window where you dropped it. An island on
  the left, *Suggested*, offers to tile the window beside the apps you used last ("+ Mail"), and one
  on the right, *Presets*, holds yours. A name cut short scrolls while you aim at its tile.
- **Presets.** *New preset* in the menu offers two ways. *From the current desktop* saves the windows
  on your screen as a preset straight away and lets you name it in the list. *Draw one…* opens the
  editor instead: the screen
  dims, drag to draw a box, drag a box to move it, pull its edges to resize it, and click *Choose an
  app* in each box to say what opens there. Clicking a preset in the menu (or dropping a window on it
  in the notch) puts each app back in its place, opening any that are closed, and an Undo grows out
  of the notch for a few seconds; its pencil opens it in the editor again.
- **Layouts.** *New layout* offers the same two: *Draw one…* opens the same editor with empty boxes,
  for the picker, and *From the current desktop* saves one with a box where each window is. Every
  layout, built-in or your own, is listed in the menu with a pencil to change it, a switch for whether
  the notch offers it and a bin to delete it. Deleted built-ins come back as they first were with
  *Restore built-in layouts*. Drag either list by a row's grip to reorder it; the notch offers its
  layouts in the same order as the menu. There is no separate Settings window: it is all in the menu.
- **Shortcuts.** In the editor every layout box has *Add shortcut*: click it and press the keys (with
  ⌘, ⌃ or ⌥, or a function key alone). Pressing them in any app sends the window you're in to that
  box, on the screen it is on. A preset's shortcut sits in its editor's toolbar and applies it, as
  clicking it in the menu does. A combination does one thing: giving it to something new takes it
  from whatever had it. esc keeps the shortcut a box had; ⌫ removes it. The menu's *Shortcuts* list
  shows every one with its keys: switch one off to let its keys through to your apps for a while,
  click its pencil to change it or its bin to remove it.

On its first run MacsPane opens a short setup window. You practise the drag on sample windows, grant
Accessibility (the one permission it needs, to move other apps' windows) and try the drag on a real
one, pick the layouts the notch offers, and switch on any suggested shortcuts (⌃⌥← and ⌃⌥→ for the
halves, ⌃⌥↩ to fill, ⌃⌥C to centre), trying them on the samples first. The menu's Setup button opens
it again.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsPaneCore` | Pure logic with no AppKit: layouts, presets, snap zones, the picker's geometry, and the config file. Unit-tested. |
| `MacsPaneKit` | The app: the drag tracker (global mouse monitors, never consuming events), the notch panel and picker, Accessibility window moves, MacsPane's page of the dropdown, the box editor and setup. `MacsPaneFeature` is what mac++ starts. |

Your choices are saved to `~/Library/Application Support/MacsPane/config.json`. Every field decodes with a
default, so a file from an older version never resets your presets.

`mac-plus-plus --snapshot-macspane <dir>` renders each surface (the dropdown, the notch states, the box editor,
setup and the permission card) to PNGs without touching your windows.
