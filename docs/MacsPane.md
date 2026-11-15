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
- **Presets.** *Add* beside *Presets* in the menu offers two ways. *From the current desktop* saves the windows
  on your screen as a preset straight away and lets you name it in the list. *Draw one…* opens the
  editor instead: the screen
  dims, drag to draw a box, drag a box to move it, pull its edges to resize it, and click *Choose an
  app* in each box to say what opens there. Clicking a preset in the menu (or dropping a window on it
  in the notch) puts each app back in its place, opening any that are closed, and an Undo grows out
  of the notch for a few seconds; its pencil opens it in the editor again.
- **Layouts.** *Add* beside *Layouts in the notch* offers the same two: *Draw one…* opens the same editor with empty boxes,
  for the picker, and *From the current desktop* saves one with a box where each window is. Every
  layout, built-in or your own, is listed in the menu with a pencil to change it, a bin to delete it
  and a switch for whether the notch offers it. Deleted built-ins come back
  as they first were with *Restore built-in layouts*. Drag a row of either list by its picture to
  reorder it; the notch offers its layouts in the same order as the
  menu. Every MacsPane setting is on its page of the menu; *Hold for*, how long a dragged window rests
  on the notch before the picker opens, is under the lists.
- **Shortcuts.** *Add* beside *Shortcuts* opens *New Shortcut* in the menu: press the keys (with ⌘, ⌃
  or ⌥, or a function key alone), pick a layout or a preset, click the box on the big screen under it, and *Add Shortcut*.
  The editor gives them too: every layout box has *Add shortcut*. Pressing a box's keys in any app
  sends the window you're in to that box, on the screen it is on. A preset's shortcut sits in its editor's toolbar and applies it, as
  clicking it in the menu does. A combination does one thing: giving it to something new takes it
  from whatever had it. esc keeps the shortcut a box had; ⌫ removes it. The menu's *Shortcuts* list
  shows every one with its keys: switch one off to let its keys through to your apps for a while,
  click its pencil to change it or its bin to remove it.

MacsPane's lessons are part of mac++'s onboarding, after mac++'s own Accessibility step (the one
permission MacsPane needs, to move other apps' windows). You see the drag at work, practise it on sample
windows, pick the layouts the notch offers, and switch on any suggested shortcuts (⌃⌥← and ⌃⌥→ for the
halves, ⌃⌥↩ to fill, ⌃⌥C to centre), trying them on the samples first. MacsPane's Help, the ?
beside its name at the top of its page, explains each part and can play the lessons again.

## The settings file

Everything lives in `~/Library/Application Support/MacsPane/config.json`, written to be edited by hand,
by scripts or by an AI agent. MacsPane watches it: a change applies as soon as it's saved. A file that
isn't JSON is never written over, the last good settings keep running, and MacsPane's page names the
line. MacsPane's Help has *Show the settings file*, which finds it in Finder.
Every field is optional, and anything a field can't use (keys that name nothing, a shortcut whose
preset doesn't exist) is left out alone, so a mistake never resets your presets.

```json
{
  "$schema": "./config.schema.json",
  "dwellMs": 600,
  "windows": { "dragBarLayoutIDs": ["halves", "thirds", "fill"] },
  "presets": [
    { "id": "work", "name": "Work", "slots": [
      { "region": "leftTwoThirds", "binding": { "kind": "app", "bundleID": "com.microsoft.VSCode" } },
      { "region": "rightThird", "binding": { "kind": "app", "bundleID": "com.apple.Safari" }, "launchIfClosed": true }
    ] }
  ],
  "shortcuts": [
    { "keys": "ctrl+opt+left", "action": { "kind": "layoutBox", "layoutID": "halves", "box": 0 } },
    { "keys": "hyper+W", "action": { "kind": "preset", "id": "work" } }
  ]
}
```

Keys are written as MacsBored writes them (`ctrl+opt+left`, `hyper+1`, `F13`). A box is a zone's name
(`leftHalf`, `topRightQuarter`, `maximize`…) or `{ "kind": "custom", "rect": { "x", "y", "width",
"height" } }` in fractions of the screen, measured from the bottom left. Ids are whatever you like; a
shortcut names a preset or layout by its id and a box by its number from 0. The built-in layouts are
`halves`, `twoThirds`, `fill`, `desk`, `quarters`, `thirds` and `centre`. `config.schema.json` beside the
file describes every field, with each built-in layout's boxes.

From a terminal, mac++'s executable answers three commands without starting the app:

```bash
"/Applications/mac++.app/Contents/MacOS/mac++" macspane check
```

`macspane check [file]` prints each problem with its line and exits 1 on an error (a warning is a field
MacsPane doesn't know, usually a misspelling); `macspane path` prints where the file is; `macspane schema`
prints the schema. Files from before keys were text are rewritten in this shape the first time mac++ opens them.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsPaneCore` | Pure logic with no AppKit: layouts, presets, snap zones, the picker's geometry, and the config file. Unit-tested. |
| `MacsPaneKit` | The app: the drag tracker (global mouse monitors, never consuming events), the notch panel and picker, Accessibility window moves, MacsPane's page of the dropdown, the box editor, its lessons and its help text. `MacsPaneFeature` is what mac++ starts. |

`mac-plus-plus --snapshot-macspane <dir>` renders each surface (the dropdown, the notch states, the box editor,
its onboarding lessons and the permission card) to PNGs without touching your windows.
