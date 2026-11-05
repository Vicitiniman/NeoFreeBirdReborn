import Foundation

// The production adapter is compiled on macOS with these small UIKit stand-ins.
// Real UIKit rendering and device navigation remain separate checks.
public final class UIImage: NSObject {
    let name: String
    public init?(systemName: String) { name = systemName; super.init() }
}
public class UIViewController: NSObject {
    var marker = ""
    convenience init(_ marker: String) { self.init(); self.marker = marker }
}
private struct Identifier { let rawValue: String }
private enum ReTap { case scrollToTop; case custom(() -> Void) }
private enum LongPress { case action(() -> Void) }
private struct Tab {
    let identifier: Identifier
    let icon: UIImage
    let selectedIcon: UIImage
    let accessibilityLabel: String
    let makeRootViewController: () -> UIViewController
    let reTapAction: ReTap
    let longPressAction: LongPress?
}
private final class Controller: NSObject {
    var orderedTabs: [Tab]
    var selectedIdentifier = Identifier(rawValue: "home")
    init(_ tabs: [Tab]) { orderedTabs = tabs }
}
private final class FactoryCapture { let marker = "retained-factory" }

@main struct GlassNavigationTests {
    static func main() {
        func tab(_ id: String, _ revision: String = "") -> Tab {
            Tab(identifier: Identifier(rawValue: id), icon: UIImage(systemName: id)!,
                selectedIcon: UIImage(systemName: id + ".fill")!, accessibilityLabel: id,
                makeRootViewController: { UIViewController(id + revision) },
                reTapAction: .scrollToTop, longPressAction: nil)
        }
        let native = [tab("home"), tab("search"), tab("grok"), tab("notifications"), tab("messages"), tab("future-native")]
        let controller = Controller(native)
        let account = NSObject()
        let defaultPages = ["home", "guide", "ntab", "messages"]
        var generation: UInt = 1
        var writes = 0
        var settingsCreations = 0
        var likesCreations = 0
        BHTGlassNavigationRuntime.testReplace = { value, selected, target in
            guard let array = value as? [Tab], let target = target as? Controller else { return false }
            writes += 1
            target.orderedTabs = array
            target.selectedIdentifier = Identifier(rawValue: selected)
            return true
        }
        func apply(_ pages: [String]? = nil, _ activeAccount: NSObject? = nil) {
            _ = BHTGlassNavigationRuntime.apply(to: controller, account: activeAccount ?? account, generation: generation,
                visiblePages: pages ?? defaultPages, registry: [], settingsFactory: {
                    settingsCreations += 1; return UIViewController("settings")
                }, likesFactory: {
                    likesCreations += 1; return UIViewController("likes")
                })
        }
        func ids() -> [String] { controller.orderedTabs.map { $0.identifier.rawValue } }
        func pageIDs() -> [String] {
            ids().map { BHTGlassNavigationRuntime.canonicalPage($0, registry: []) ?? $0 }
        }
        apply()
        precondition(pageIDs() == ["home", "guide", "ntab", "messages", "nfb_settings", "future-native"])
        precondition(settingsCreations == 0 && likesCreations == 0, "Factories stay lazy")
        let settingsID = ids()[4]
        precondition(controller.orderedTabs[0].makeRootViewController().marker == "home", "Keep native destination factories")
        precondition(controller.orderedTabs[4].makeRootViewController().marker == "settings")
        precondition(native[0].identifier.rawValue == "home" && native[0].accessibilityLabel == "home", "Cloning must not mutate the template")
        let stableWrites = writes
        for _ in 0..<100 { apply() }
        precondition(writes == stableWrites, "Stable layout must not replace tabs or create a startup loop")

        generation += 1
        controller.selectedIdentifier = Identifier(rawValue: "notifications")
        apply(["home", "ntab", "likes", "guide", "messages"])
        precondition(pageIDs() == ["home", "ntab", "likes", "guide", "nfb_settings", "messages", "future-native"])
        precondition(controller.selectedIdentifier.rawValue == "notifications", "Retain an existing selected destination")
        precondition(controller.orderedTabs[2].makeRootViewController().marker == "likes")
        precondition(ids().contains(settingsID), "Settings identity remains stable within an account")

        generation += 1
        apply(["home", "grok", "guide", "ntab", "messages"])
        precondition(pageIDs().contains("grok") && !pageIDs().contains("likes"), "Hidden native tabs can be restored")
        precondition(controller.orderedTabs.first(where: { $0.identifier.rawValue == "grok" })?.makeRootViewController().marker == "grok")

        generation += 1
        controller.selectedIdentifier = Identifier(rawValue: "grok")
        apply(["home", "guide"])
        precondition(controller.selectedIdentifier.rawValue == "home", "Removing the selected tab lands on Home")

        let secondAccount = NSObject()
        controller.orderedTabs = [tab("home", "-new"), tab("search", "-new"), tab("notifications", "-new")]
        generation += 1
        apply(defaultPages, secondAccount)
        precondition(!ids().contains(settingsID), "Account changes get fresh owned destinations")
        precondition(!pageIDs().contains("future-native"), "Never carry native descriptors into another account")
        precondition(controller.orderedTabs[0].makeRootViewController().marker == "home-new")

        // A fresh host replacement can remove tabs without leaving stale cache entries.
        controller.orderedTabs = [tab("home", "-latest"), tab("search", "-latest")]
        apply(defaultPages, secondAccount)
        precondition(!pageIDs().contains("ntab"))
        precondition(controller.orderedTabs[0].makeRootViewController().marker == "home-latest")

        let aliases: [[String: Any]] = [["page": "home", "panelID": 2]]
        precondition(BHTGlassNavigationRuntime.canonicalPage("panel:2", registry: aliases) == "home")
        precondition(BHTGlassNavigationRuntime.canonicalPage("unrecognized", registry: aliases) == nil)
        precondition(BHTGlassNavigationRuntime.canonicalPage("panel:6", registry: [["page": "likes", "panelID": 6]]) == nil,
                     "A native Bookmarks carrier must never be confused with owned Likes")

        struct WrongTab { let identifier: Identifier; let icon: String }
        let invalid = BHTGlassNavigationRuntime.clone(WrongTab(identifier: Identifier(rawValue: "home"), icon: "wrong"),
            id: "invalid", title: "Invalid", image: UIImage(systemName: "gearshape")!, selectedImage: UIImage(systemName: "gearshape")!,
            factory: { UIViewController() })
        precondition(invalid == nil, "Reject changed native layouts before writing fields")
        let withAction = Tab(identifier: Identifier(rawValue: "home"), icon: native[0].icon, selectedIcon: native[0].selectedIcon,
            accessibilityLabel: "Home", makeRootViewController: { UIViewController() }, reTapAction: .custom({}), longPressAction: nil)
        precondition(BHTGlassNavigationRuntime.clone(withAction, id: "x", title: "x", image: native[0].icon,
            selectedImage: native[0].selectedIcon, factory: { UIViewController() }) == nil,
            "Do not copy an unrelated native action into an owned tab")
        let renamedHome = Controller([tab("new-home-format"), tab("search"), tab("notifications")])
        _ = BHTGlassNavigationRuntime.apply(to: renamedHome, account: account, generation: 1,
            visiblePages: ["home", "ntab", "guide"], registry: [],
            settingsFactory: { UIViewController() }, likesFactory: { UIViewController() })
        precondition(renamedHome.orderedTabs.first?.identifier.rawValue == "new-home-format",
                     "An unrecognized Home identifier must preserve native order")
        weak var captured: FactoryCapture?
        var held: Tab? = {
            let context = FactoryCapture()
            captured = context
            return BHTGlassNavigationRuntime.clone(native[0], id: "lifetime", title: "Lifetime",
                image: native[0].icon, selectedImage: native[0].selectedIcon,
                factory: { UIViewController(context.marker) })
        }()
        precondition(captured != nil && held?.makeRootViewController().marker == "retained-factory",
                     "An owned destination must retain its concrete factory context")
        held = nil
        precondition(captured == nil, "Removing the destination must release its factory context")
        print("PASS: concrete glass descriptors, lazy settings/Likes, ordering, selection, idle layout, account isolation and shape rejection")
    }
}
