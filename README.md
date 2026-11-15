# mac++

Two menu-bar tools for macOS in one app, behind one icon.

- **MacsPane** snaps windows: drag a window to the notch, hold it there, and drop it into a layout.
  Presets put a set of apps back where you like them. See [docs/MacsPane.md](docs/MacsPane.md).
- **MacsBored** hands macOS's own shortcuts (⌘⇥, ⌘Space, ⌃←/→, the screenshot keys and the rest) to
  Windows App, Citrix Viewer or a virtual machine while it is in front, and runs your own keyboard
  triggers everywhere else. See [docs/MacsBored.md](docs/MacsBored.md).

mac++'s mark is an apple with "++" inside. Click it in the menu bar and the dropdown opens on the page
you used last. The switcher along its top moves between MacsPane and MacsBored (⌘1 and ⌘2 do the
same). Each page is that tool's own menu, drawn the same way for both: its main switch, what it is doing
now, and its lists, each with *+ Add* on its title to make a new one. Its other settings are in
Settings, under its name. Click a section's title to fold it; each page
remembers what is folded. The foot of the dropdown belongs to the
whole app:

- **Settings** (⌘,) opens mac++'s Settings.
- **Quit mac++** (⌘Q) stops both tools; MacsBored gives macOS every shortcut back first.

Settings is one page drawn as System Settings draws a pane: which mac++ this is (its version),
Accessibility (one grant covers both tools), Open at login, and Size, which draws the whole menu
Small, Default, Large or Larger. Under *Apps*, a row for each tool opens its own settings. Each
tool's main switch stays on its page of the menu.

Settings holds settings only. What explains them is Help: the ? beside a tool's name, at the top of its
page, opens its Help (how it works, its keys, and its lessons again); the ? beside mac++ in Settings
opens mac++'s (the menu, its keys, and the onboarding again).

Settings and Help open in the dropdown itself, over the tool's page, and scroll once they
are taller than the screen allows. A navigation bar takes the switcher's place, with the page's title in the
middle and a back button named for the page it goes back to (‹ MacsPane); it and `esc` go back one
page. Only the onboarding, and each tool's editor, open windows of their own.

If mac++ doesn't have Accessibility yet, an orange line above every page says so, with a Grant button.
The apple in the menu bar turns solid while MacsBored is handing macOS's shortcuts to the app in front.

On a first run mac++ opens its onboarding: a welcome, the Accessibility grant, MacsPane's lessons,
MacsBored's lessons, then where mac++ lives in the menu bar, with Open at login.

The two used to be separate apps. Their settings stay where they were
(`~/Library/Application Support/MacsPane` and `~/Library/Application Support/MacsBored`), so mac++
picks up an existing setup as it is. mac++ has its own bundle identifier (`com.jgray.mac-plus-plus`),
so it needs Accessibility granted once, and the old MacsPane and MacsBored apps should be quit before
it starts, since the two copies would otherwise both act on the same drags and keys.

## Settings files

Each tool keeps its settings in one JSON file meant to be edited by people, scripts and AI agents as
much as through the menu. Ask an agent to "add ⌃⌥W to send the window to the left two thirds" and it
can do it in the file; the running app picks the change up as soon as it's saved.

| | MacsPane | MacsBored |
|---|---|---|
| File | `~/Library/Application Support/MacsPane/config.json` | `~/Library/Application Support/MacsBored/config.json` |
| Schema | `config.schema.json` beside it, linked by `$schema` | the same |
| Check an edit | `mac++ macspane check` | `mac++ macsbored check` |
| What's in it | presets, layouts, shortcuts, the hold time | passthrough apps, triggers, the pause keys, Caps Lock as Hyper |

Both write keys the same way (`ctrl+opt+left`, `hyper+N`, `cmd+space`) and apps by bundle ID. `check`
prints each problem as `file:line: error|warning: …` and exits 1 on an error. A file with a mistake is
never written over: the last good settings keep running and the tool's page names the line. Each tool's
Help has *Show the settings file*, which finds it in Finder. Each tool's doc has the details:
[MacsPane](docs/MacsPane.md#the-settings-file), [MacsBored](docs/MacsBored.md#the-settings-file).

## Installing a test build

Requires macOS 14 or later, on Apple silicon or Intel.

1. Open the `mac-plus-plus-<version>-<channel>.dmg` made by `scripts/release.sh` and drag mac++ into
   Applications.
2. Open mac++ from Applications. It has no Dock icon: it lives in the menu bar. On a first run its
   onboarding opens.
3. On onboarding's Accessibility step, click **Grant Access** and switch mac++ on in System Settings ›
   Privacy & Security › Accessibility.

Test builds are not signed by Apple, so macOS blocks the first open: click **Done**, then open System
Settings › Privacy & Security and click **Open Anyway** under the message about mac++. You do this once.
The disk image has these steps in *How to open mac++.txt*.

To remove mac++, quit it from its menu (which gives macOS back all its shortcuts), then delete it from
Applications and the two Application Support folders above.

## Building

The package builds with the Command Line Tools; the signed `.app` uses Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The tests need Xcode's toolchain
(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); the scripts set it themselves.

```sh
swift build              # build everything
swift test               # run both Core test suites
scripts/run.sh           # build a mac++.app bundle and open it
```

After changing the logo, `scripts/make_icon.sh` redraws the app icon files from it.

`swift run mac-plus-plus` also works, but Accessibility is granted per signed app, so a bundle signed
with a stable identity (`MACPLUSPLUS_SIGN_IDENTITY=…  scripts/run.sh`) keeps the grant across rebuilds.

For the Xcode project: `xcodegen generate`, then build the `MacPlusPlus` scheme.

The executable also takes these, for scripts, agents and looking at a change:

| Arguments | What they do |
|---|---|
| `macspane path`, `macspane check [file]`, `macspane schema` | MacsPane's settings file, without starting the app. |
| `macsbored path`, `macsbored check [file]`, `macsbored schema` | MacsBored's settings file, without starting the app. |
| `--smoke-test` | Launch, then quit after 1.5 s. |
| `--open-menu [macspane\|macsbored]` | Open the dropdown, on that page. |
| `--open-onboarding [macspane\|macsbored]` | Open onboarding, at that tool's lessons. |
| `--open-settings` | Open the dropdown on mac++'s Settings. |
| `--open-help [macspane\|macsbored]` | Open the dropdown on that tool's Help, or on mac++'s. |
| `--open-new-shortcut` | Open the dropdown on MacsPane's New Shortcut page. |
| `--open-editor macspane` | Open MacsPane's box editor on a new preset. |
| `--open-editor remap\|open\|shortcut\|passthrough` | Open the dropdown on MacsBored's editor, on a new entry of that kind. |
| `--snapshot-menu <dir>` | Write the dropdown's pages, their Help and MacsPane's New Shortcut, Settings and mac++'s Help, light and dark, as PNGs, then quit. |
| `--snapshot-windows <dir>` | Write every onboarding step as PNGs, then quit. |
| `--export-icon <dir>` | Write the app icon and menu-bar marks as PNGs (`scripts/make_icon.sh` uses it). |
| `--snapshot-macspane <dir>` | Write MacsPane's other surfaces as PNGs, then quit. |

### Releasing

`scripts/release.sh beta.1` runs the tests, builds for Apple silicon and Intel, signs the app and packs
it in `dist/mac-plus-plus-<version>-beta.1.dmg` with its SHA-256. The version is in `VERSION`; the build
number is the commit count, so every release is newer than the last.

To give it to other people, sign it with a Developer ID (from the Apple Developer Program) and have
Apple notarize it:

```sh
xcrun notarytool store-credentials macplusplus --apple-id <email> --team-id <TEAMID>   # once
MACPLUSPLUS_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
MACPLUSPLUS_NOTARY_PROFILE=macplusplus scripts/release.sh
```

Every release signed with the same Developer ID keeps the Accessibility permission people already gave.
Without an identity the script makes an ad-hoc test build whose signature asks only for mac++'s bundle
identifier, so testers keep Accessibility across test builds; any other ad-hoc app claiming that
identifier would get it too, so use a Developer ID before a wide release.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsShared` | What both tools are built from, so they look and behave alike: the tabbed dropdown under the menu-bar icon (`TabbedMenuController`) with its app-wide footer under each tool's page; the page every tool's menu is drawn by (`MenuPageView`, fed a `MenuPageContent`); the cards, tiles, rows and lesson steps every window uses; the pages opened over a tool's page with their navigation bar, and the System Settings-style rows they are made of (`SettingsSection`, `SettingsLink`…); the onboarding window (`OnboardingView`, made of each tool's `OnboardingPart`); the window controller; Open at login; and mac++'s logo. |
| `MacsSettings` | What both settings files share: keys as text (`ctrl+opt+left`) and a JSON reader that knows each value's line, for `check`. No AppKit. |
| `MacsPaneCore`, `MacsPaneKit` | MacsPane: pure logic with its tests, then the app (`MacsPaneFeature`). |
| `MacsBoredCore`, `MacsBoredKit` | MacsBored: pure logic with its tests, then the app (`MacsBoredFeature`). |
| `MacPlusPlusKit` | The app itself: the menu-bar icon, both tools started and stopped together, mac++'s own onboarding steps (welcome, Accessibility, the menu bar) and its Settings. |
| `mac-plus-plus` | The executable that boots `MacPlusPlusKit`. |

Each tool's Core has no AppKit and is unit-tested. A new tool joins by adding its own Core and Kit, a
`MenuPageTab` for its page (its `MenuPageContent` and `HelpContent`), an `OnboardingPart` for its lessons,
and a line for each in `MacPlusPlusAppDelegate`.

Both tools' full histories are in this repository's history: MacsPane from `expiracy/macs-pane` and
MacsBored from `expiracy/macs-key-board`.

## License

Copyright (C) 2026 James Gray

mac++ is free software: you can redistribute it and/or modify it under the terms of the GNU Affero
General Public License as published by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version. Anything built from it, including a modified version you only offer
to others over a network, must be released under the same license with its source. See
[LICENSE](LICENSE) for the full text.
