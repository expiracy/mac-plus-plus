import MacPlusPlusKit

// mac++'s entry point. All boot logic lives in `MacPlusPlusKit.MacPlusPlusApp`, shared with the
// bundled app (App/main.swift) so they can't drift.
//   swift run mac-plus-plus                  Launch (stays running in the menu bar).
//   swift run mac-plus-plus --smoke-test     Boot, then quit after ~1.5 s.
//   swift run mac-plus-plus macsbored check  Check MacsBored's config file.
MacPlusPlusApp.run()
