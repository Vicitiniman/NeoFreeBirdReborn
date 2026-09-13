import Foundation

private final class Feed: NSObject {}
private class Provider {
    let homeTimelineViewController = Feed()
    let latestTimelineViewController = Feed()
    var selectedViewController: Feed?
}
private final class LazyProvider: Provider {
    var cachedVCs: [String: Feed] = [:]
}
private final class Container {
    var timelineProvider: Provider?
}
private final class UnknownContainer {
    let selectedViewController = Feed()
}

@main
struct HomeTimelineRuntimeTests {
    static func main() {
        let container = Container()
        precondition(BHTHomeTimelineRuntime.primaryTimelineController(in: container) == nil)
        for provider in [Provider(), LazyProvider()] {
            container.timelineProvider = provider
            for selected in [provider.homeTimelineViewController, provider.latestTimelineViewController] {
                provider.selectedViewController = selected
                let resolved = BHTHomeTimelineRuntime.primaryTimelineController(in: container)
                precondition(resolved === provider.homeTimelineViewController)
                precondition(resolved !== provider.latestTimelineViewController)
            }
        }
        container.timelineProvider = nil
        precondition(BHTHomeTimelineRuntime.primaryTimelineController(in: container) == nil)
        precondition(BHTHomeTimelineRuntime.primaryTimelineController(in: UnknownContainer()) == nil)
        print("PASS: eager/lazy primary feed ownership, provider replacement, missing fields, and Following isolation")
    }
}
