import Foundation
import Combine

@_cdecl("BHTInvokeTwitterDashArraySetter")
func unusedNativeSetter(_ array: UInt, _ object: UnsafeMutableRawPointer,
                        _ setter: UnsafeMutableRawPointer) {
    fatalError("Tests must use the typed fixture setter")
}

private struct Row {
    let title: String
    let iconName: String
    let revision: Int
}

private final class Source: ObservableObject {
    @Published var primaryItems: [Row] = []
    @Published var folderItems: [Row] = []
    @Published var tertiaryItems: [Row] = []
}

private final class Controller: NSObject {
    let dataSource = Source()
}

@main
struct SidebarRuntimeTests {
    static func main() {
        let key = "bht_sidebar_navigation_visible"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        let previousGrok = defaults.object(forKey: "hide_grok_sidebar")
        defaults.set(false, forKey: "hide_grok_sidebar")
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            if let previousGrok { defaults.set(previousGrok, forKey: "hide_grok_sidebar") }
            else { defaults.removeObject(forKey: "hide_grok_sidebar") }
        }
        let controller = Controller()
        let source = controller.dataSource
        var writes = 0
        BHTSidebarRuntime.testSetter = { property, value, object in
            guard let source = object as? Source, let rows = value as? [Row] else { return false }
            writes += 1
            switch property {
            case "primaryItems": source.primaryItems = rows
            case "folderItems": source.folderItems = rows
            case "tertiaryItems": source.tertiaryItems = rows
            default: return false
            }
            return true
        }
        func rows(_ revision: Int) -> [Row] {
            [Row(title: "Profil", iconName: "account_stroke", revision: revision),
             Row(title: "Listes", iconName: "lists_stroke", revision: revision),
             Row(title: "Actualités", iconName: "news_stroke", revision: revision),
             Row(title: "Future X feature", iconName: "unknown_icon", revision: revision)]
        }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        defaults.set(["profile", "profile", "invalid"], forKey: key)
        source.primaryItems = rows(0)
        precondition(BHTSidebarRuntime.applyResult(forDashContentController: controller) == 3)
        precondition(source.primaryItems.map(\.title) == ["Profil", "Future X feature"])
        let initialWrites = writes
        precondition(BHTSidebarRuntime.applyResult(forDashContentController: controller) == 1)
        drain()
        precondition(writes == initialWrites, "Idempotent apply must not republish")
        for revision in 1...5 {
            source.primaryItems = rows(revision)
            drain()
            precondition(source.primaryItems.map(\.title) == ["Profil", "Future X feature"])
            precondition(source.primaryItems.allSatisfy { $0.revision == revision })
        }
        precondition(writes == initialWrites + 5, "Each native refresh should trigger one rewrite")
        defaults.set([String](), forKey: key)
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.map(\.title) == ["Future X feature"])
        defaults.set(["news", "lists", "profile"], forKey: key)
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.map(\.title) == ["Actualités", "Listes", "Profil", "Future X feature"])
        precondition(source.primaryItems.allSatisfy { $0.revision == 5 }, "Unhiding must restore the latest native values")
        drain()
        let settledWrites = writes
        drain()
        precondition(writes == settledWrites, "The observer must not feed back into itself")
        let grok = Row(title: "Try Grok Bot", iconName: "grok_bot_logo", revision: 6)
        source.primaryItems = [grok]
        defaults.set(["grok_bot"], forKey: key)
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.map(\.title) == ["Try Grok Bot"])
        defaults.set(true, forKey: "hide_grok_sidebar")
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.isEmpty, "The existing Grok switch must hide the new bot")
        source.primaryItems = [grok]
        drain()
        precondition(source.primaryItems.isEmpty, "Native refresh must not resurrect Grok Bot")
        defaults.set(false, forKey: "hide_grok_sidebar")
        defaults.set([String](), forKey: key)
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.map(\.title) == ["Try Grok Bot"], "Only the navigation switch controls the legacy bot row after moving its editor")
        defaults.set(["grok_bot"], forKey: key)
        _ = BHTSidebarRuntime.applyResult(forDashContentController: controller)
        precondition(source.primaryItems.map(\.title) == ["Try Grok Bot"])
        let subscriptionSource = Source()
        let subscriptions = Row(title: "Abonnements", iconName: "subscriptions_stroke", revision: 1)
        let premium = Row(title: "Premium", iconName: "verified_stroke", revision: 1)
        let nativeSettings = Row(title: "Settings and privacy", iconName: "settings_stroke", revision: 1)
        defaults.set(["profile", "lists"], forKey: key)
        subscriptionSource.primaryItems = [subscriptions, premium, nativeSettings]
        BHTSidebarRuntime.apply(to: subscriptionSource)
        precondition(subscriptionSource.primaryItems.map(\.title) == ["Settings and privacy"],
                     "New Subscriptions must follow an existing saved selection, retaining native Settings")
        defaults.set(["subscriptions", "blue"], forKey: key)
        BHTSidebarRuntime.apply(to: subscriptionSource)
        precondition(subscriptionSource.primaryItems.map(\.title) == ["Abonnements", "Premium", "Settings and privacy"],
                     "Subscriptions and Premium are separate, restorable choices")
        defaults.set(["blue", "subscriptions"], forKey: key)
        BHTSidebarRuntime.apply(to: subscriptionSource)
        precondition(subscriptionSource.primaryItems.map(\.title) == ["Premium", "Abonnements", "Settings and privacy"])
        defaults.set([String](), forKey: key)
        BHTSidebarRuntime.apply(to: subscriptionSource)
        subscriptionSource.primaryItems = [Row(title: "Subscribe", iconName: "new_icon", revision: 2), nativeSettings]
        drain()
        precondition(subscriptionSource.primaryItems.map(\.title) == ["Settings and privacy"],
                     "Subscribe title fallback must stay hidden after a native refresh")
        defaults.removeObject(forKey: key)
        BHTSidebarRuntime.apply(to: subscriptionSource)
        precondition(subscriptionSource.primaryItems.contains { $0.title == "Subscribe" && $0.revision == 2 },
                     "Restore uses the latest native Subscriptions row")
        print("PASS: sidebar refresh, localization, duplicate preferences, hide-all, restore, and observer idempotence")
        print("PASS: localized Subscriptions, Premium isolation, saved selection, reorder, native refresh and restore")
    }
}
