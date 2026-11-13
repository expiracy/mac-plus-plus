# MacsBored

MacsBored is one of the two pages of [mac++](../README.md)'s menu-bar dropdown. Installing, building and
releasing are in the README; this page is what MacsBored does.

Your Mac's shortcuts, sent to the computer you're remoting into.

MacsBored is a menu-bar app for macOS, a sibling of [MacsPane](https://github.com/expiracy/macs-pane).
When Windows App, Citrix Viewer or a virtual machine is in front, macOS stops taking ⌘⇥, ⌘Space, ⌃←/→,
the screenshot keys and the rest, so they reach the session as they would on a PC. Switch to any other
app and macOS has them back. Alongside that it runs your own shortcuts, BetterTouchTool style.

## Using it

- **Passthrough apps.** Each names the apps it covers, when it acts, and which of macOS's shortcuts go
  to the app instead: the app switcher, Spotlight, Mission Control, Spaces, screenshots, input sources,
  the Dock and Notification Centre, keyboard navigation, Zoom and Help search. The menu's *Now* box
  offers to add the app in front; setup offers any remote-desktop app installed on first run.
- **Conditions.** A passthrough or trigger can wait for any of these: the window is full screen, the
  window fills the screen, the window title contains some text, an external display is connected, the
  Mac is on battery, the time is between two times, or Caps Lock is on. Each can be turned round
  (*Unless*), and they combine as *All* or *Any*.
- **Pause.** ⌃⌥⌘P inside a passthrough app gives macOS its shortcuts back so you can ⌘⇥ out. It resumes
  by itself once another app is in front.
- **Keys.** *Send every key straight to the app* also keeps other apps' global shortcuts (Raycast,
  Alfred, window managers) out of the session; it is off until you switch it on. *Modifier keys* can
  swap ⌘ and ⌃, so ⌘C is Ctrl+C in Windows and ⌃ is the Windows key.
- **Triggers.** Keys that do one thing, anywhere or only in some apps, under the same conditions: press
  other keys instead (a remap), open an app, a link or a file, run one of Apple's Shortcuts, or pass just
  those keys straight to the app in front. A trigger with no apps works everywhere except inside a
  passthrough app, whose keys belong to the session; name the passthrough app to have it work there too.
  Giving a trigger keys another trigger had takes them from it.
- **Caps Lock is Hyper.** Caps Lock holds ⌃⌥⇧⌘, a combination no app uses, for your triggers. It is
  remapped with `hidutil` for this login session and put back when you switch it off or quit; if another
  tool already remaps keys, it stays off.

There is no separate Settings window: it is all in the menu. *New* opens the editor, whose tabs pick
what you're making (Remap Keys, Open, Run Shortcut, Passthrough), and the pencil on a row opens it on
that entry. The menu's Setup button opens setup again.

## The settings file

Everything lives in `~/Library/Application Support/MacsBored/config.json`, written to be edited by hand,
by scripts or by an AI agent. MacsBored watches it: a valid change applies as soon as it's saved. A file
with a mistake is left alone, the last good settings keep running, and the menu names the line.

```json
{
  "enabled": true,
  "pauseKeys": "ctrl+opt+cmd+P",
  "passthrough": [{ "name": "Windows App", "apps": ["com.microsoft.rdc.macos"] }],
  "triggers": [
    { "name": "Open Notes", "keys": "ctrl+opt+N", "action": { "openApp": "com.apple.Notes" } },
    { "name": "Focus", "keys": "hyper+F", "action": { "runShortcut": "Start a Focus timer" },
      "when": [{ "unless": "onBattery" }] }
  ]
}
```

Keys are text (`ctrl+opt+cmd+P`, `hyper+N`, `cmd+space`; the menu's `⌃⌥⌘P` works too), and a trigger
can have several as a list (`"keys": ["cmd+space", "cmd+tab"]`), any of which sets it off. Apps are bundle
IDs, times are `"09:00"`, and entries need no IDs. An action is one of `sendKeys`, `openApp`,
`runShortcut`, `passThrough` (`true`) or `open`. `config.schema.json` beside the file describes every
field. Fields MacsBored doesn't know are kept as they are. The first version's file
(`~/Library/Application Support/MacsKeyBored/config.json`) is converted once.

From a terminal, mac++'s executable answers three commands without starting the app:

```bash
"/Applications/mac++.app/Contents/MacOS/mac++" macsbored check
```

`macsbored check [file]` prints each problem with its line and exits 1 on an error; `macsbored path` prints where
the file is; `macsbored schema` prints the schema.

## How passthrough works

macOS's own shortcuts are "symbolic hot keys" that the WindowServer handles before any app sees the
keys. While a passthrough app is in front, MacsBored switches the chosen ones off with the private
SkyLight call AltTab also uses (`CGSSetSymbolicHotKeyEnabled`), and switches them back on when it isn't.

It only ever switches back on what it switched off, and never touches a shortcut that is off in System
Settings. On macOS 26 the WindowServer reports every hot key as off, so MacsBored reads System
Settings' record (`com.apple.symbolichotkeys`) instead. The list of what it switched off is written to
disk before each change, so a crash or a force quit is undone on the next launch, and quitting (⌘Q,
`kill`, Ctrl-C) puts everything back.

An app's own menu shortcuts, such as ⌘Q or ⌘H in Windows App itself, belong to that app rather than to
macOS, so they stay with it.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsBoredCore` | Pure logic with no AppKit: profiles, conditions, triggers, the passthrough plan, the key router, the hot-key ledger, the settings file and its schema, and the editor's draft. Unit-tested. |
| `MacsBoredKit` | The app: the keyboard event tap (on its own thread), the system-shortcut switch, the Accessibility reads, MacsBored's page of the dropdown, the editors and setup. `MacsBoredFeature` is what mac++ starts. |

`mac-plus-plus --open-menu macsbored`, `--open-editor remap|open|shortcut|passthrough` and
`--open-setup macsbored` open those surfaces straight away, for looking at them without clicking through.
