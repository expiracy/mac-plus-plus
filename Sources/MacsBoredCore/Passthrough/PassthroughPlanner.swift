import Foundation

/// Decides what passthrough does from the profiles and what is in front: every switched-on profile
/// that covers the front app and whose conditions hold acts, together (one sending the app your
/// shortcuts, another making ⌥ its Windows key): the shortcuts any of them sends, every key if any
/// asks, and the first modifier layout that changes anything. With none, or while paused, macOS keeps
/// all its shortcuts.
public enum PassthroughPlanner {
    public static func plan(profiles: [PassthroughProfile], context: AppContext,
                            paused: Bool = false) -> PassthroughPlan {
        let acting = paused ? [] : profiles.filter {
            $0.isEnabled && $0.covers(bundleID: context.bundleID) && $0.conditions.isSatisfied(by: context)
        }
        guard let first = acting.first else { return .inactive }
        return PassthroughPlan(profileID: first.id, profileName: first.name, processID: context.processID,
                               disabledHotKeys: acting.reduce(into: Set<Int>()) { $0.formUnion($1.systemShortcuts.hotKeyIDs) },
                               captureAllKeys: acting.contains(where: \.captureAllKeys),
                               modifierLayout: acting.first(where: { $0.modifierLayout != .asIs })?.modifierLayout ?? .asIs)
    }
}
