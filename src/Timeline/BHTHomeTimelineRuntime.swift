import Foundation

// X 12.24.1's eager and lazy Home providers both retain an explicitly named
// homeTimelineViewController, separate from their Following/filtered feeds.
// Read those Swift fields without assuming ivar offsets or tab indices.
@objc(BHTHomeTimelineRuntime)
public final class BHTHomeTimelineRuntime: NSObject {
    private static func field(_ name: String, in object: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: object)
        for _ in 0..<16 {
            guard let current = mirror else { break }
            if let value = current.children.first(where: { $0.label == name })?.value {
                let wrapped = Mirror(reflecting: value)
                return wrapped.displayStyle == .optional
                    ? wrapped.children.first?.value : value
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    @objc(primaryTimelineControllerInContainer:)
    public static func primaryTimelineController(in container: AnyObject) -> AnyObject? {
        guard let provider = field("timelineProvider", in: container),
              let controller = field("homeTimelineViewController", in: provider),
              Mirror(reflecting: controller).displayStyle == .class else { return nil }
        return controller as AnyObject
    }
}
