import Foundation
import Darwin
import ObjectiveC
import SwiftShims
#if canImport(UIKit)
import UIKit
#endif

// These are the stdlib entry points used by Mirror's field reflection. The
// build SDK does not ship Swift's private SPI interface, but does ship the
// shared C metadata structure. Keep the declarations identical to the runtime.
@_silgen_name("swift_reflectionMirror_recursiveCount")
private func BHTGlassFieldCount(_ type: Any.Type) -> Int
@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func BHTGlassFieldOffset(_ type: Any.Type, index: Int) -> Int
@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func BHTGlassFieldMetadata(_ type: Any.Type, index: Int,
                                  fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type
@_silgen_name("swift_retain")
private func BHTGlassRetain(_ object: UnsafeRawPointer) -> UnsafeRawPointer
@_silgen_name("swift_release")
private func BHTGlassRelease(_ object: UnsafeRawPointer)

// A function stored in a concrete struct uses its concrete return convention.
// UnsafeMutablePointer<Function>.pointee instead reabstracts it to an indirect
// result. Copy this concrete slot's representation and balance its context.
private struct BHTGlassFactorySlot {
    var factory: () -> UIViewController
}

@_silgen_name("BHTInvokeGlassReplaceTabs")
private func BHTInvokeGlassReplaceTabs(
    _ array: UInt, _ identifier0: UInt, _ identifier1: UInt,
    _ object: UnsafeMutableRawPointer, _ function: UnsafeMutableRawPointer
)

fileprivate final class BHTGlassCache {
    weak var controller: AnyObject?
    weak var account: AnyObject?
    var originals: Any?
    var lastStorage: UInt = 0
    var generation: UInt = 0
    var accountToken = UUID().uuidString
    var applying = false
    var metadata: [[String: Any]] = []
    init(_ controller: AnyObject) { self.controller = controller }
}

// Preserve the host's concrete Tab values, factories and actions. Only owned
// destinations are cloned, with every assigned field checked by runtime type
// and bounds. Unknown layouts/exports leave X's native array untouched.
@objc(BHTGlassNavigationRuntime)
public final class BHTGlassNavigationRuntime: NSObject {
    static let replaceSymbol = "$s11XNavigation16TabBarControllerC11replaceTabs_9selectingySayAC0B0VG_AC0B10IdentifierVtF"
    private static var caches: [ObjectIdentifier: BHTGlassCache] = [:]
    private static var diagnostics: [String: Any] = ["state": "notObserved"]
    #if BHT_GLASS_TESTS
    static var testReplace: ((Any, String, AnyObject) -> Bool)?
    #endif

    @objc(needsUpdateForController:account:generation:)
    public static func needsUpdate(for controller: AnyObject, account: AnyObject?, generation: UInt) -> Bool {
        guard let cache = caches[ObjectIdentifier(controller)] else { return true }
        if cache.applying { return false }
        guard
              cache.account === account, cache.generation == generation,
              let ivar = class_getInstanceVariable(type(of: controller), "orderedTabs") else { return true }
        let offset = ivar_getOffset(ivar)
        guard offset >= MemoryLayout<UInt>.size,
              offset + MemoryLayout<UInt>.size <= class_getInstanceSize(type(of: controller)) else { return true }
        let storage = Unmanaged.passUnretained(controller).toOpaque().advanced(by: offset).load(as: UInt.self)
        return storage != cache.lastStorage
    }

    private static func field(_ value: Any, _ name: String) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            if let child = current.children.first(where: { $0.label == name }) { return child.value }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func rawID(_ tab: Any) -> String? {
        guard let identifier = field(tab, "identifier") else { return nil }
        return field(identifier, "rawValue") as? String
    }

    private static func storedFields(_ type: Any.Type) -> [String: (offset: Int, type: Any.Type)]? {
        let count = BHTGlassFieldCount(type)
        guard count > 0 && count <= 64 else { return nil }
        var fields: [String: (offset: Int, type: Any.Type)] = [:]
        for index in 0..<count {
            var metadata = _FieldReflectionMetadata()
            let childType = BHTGlassFieldMetadata(type, index: index, fieldMetadata: &metadata)
            defer { metadata.freeFunc?(metadata.name) }
            guard let name = metadata.name, unsafeBitCast(childType, to: UInt.self) != 0,
                  metadata.isStrong else { return nil }
            fields[String(cString: name)] = (BHTGlassFieldOffset(type, index: index), childType)
        }
        return fields.count == count ? fields : nil
    }

    static func canonicalPage(_ identifier: String, registry: [[String: Any]]) -> String? {
        if identifier.hasPrefix("nfb.settings.") { return "nfb_settings" }
        if identifier.hasPrefix("nfb.likes.") { return "likes" }
        let key = identifier.lowercased()
        let aliases = ["home": "home", "search": "guide", "explore": "guide", "guide": "guide",
                       "notifications": "ntab", "notification": "ntab", "ntab": "ntab",
                       "chat": "messages", "chats": "messages", "messages": "messages", "dms": "messages",
                       "grok": "grok", "communities": "communities", "bookmarks": "bookmarks",
                       "profile": "profile", "lists": "lists", "premium": "premium"]
        if let page = aliases[key] { return page }
        for entry in registry {
            guard let page = entry["page"] as? String, page != "likes" else { continue }
            if key == page.lowercased() { return page }
            if let number = entry["panelID"] as? NSNumber {
                let panel = number.stringValue
                if [panel, "panel_" + panel, "panel:" + panel, "panel-" + panel].contains(key) { return page }
            }
        }
        return nil
    }

    // The clone never assumes a fixed offset or writes to a live host value.
    static func clone<T>(_ template: T, id: String, title: String,
                         image: UIImage, selectedImage: UIImage,
                         factory: @escaping () -> UIViewController) -> T? {
        guard Mirror(reflecting: template).displayStyle == .struct,
        let fields = storedFields(T.self), let identifier = fields["identifier"], let icon = fields["icon"],
        let selectedIcon = fields["selectedIcon"], let label = fields["accessibilityLabel"],
        let root = fields["makeRootViewController"],
        icon.type == UIImage.self, selectedIcon.type == UIImage.self,
        label.type == String.self, root.type == (() -> UIViewController).self,
        let longPress = field(template, "longPressAction"),
        Mirror(reflecting: longPress).displayStyle == .optional,
        Mirror(reflecting: longPress).children.isEmpty,
        let retap = field(template, "reTapAction"),
        Mirror(reflecting: retap).displayStyle == .enum,
        Mirror(reflecting: retap).children.isEmpty else { return nil }
        guard let identifierValue = field(template, "identifier"),
              Mirror(reflecting: identifierValue).displayStyle == .struct,
              let identifierFields = storedFields(identifier.type), identifierFields.count == 1,
              let raw = identifierFields["rawValue"], raw.type == String.self else { return nil }
        let writes = [(identifier.offset + raw.offset, MemoryLayout<String>.size, MemoryLayout<String>.alignment),
                      (icon.offset, MemoryLayout<UIImage>.size, MemoryLayout<UIImage>.alignment),
                      (selectedIcon.offset, MemoryLayout<UIImage>.size, MemoryLayout<UIImage>.alignment),
                      (label.offset, MemoryLayout<String>.size, MemoryLayout<String>.alignment),
                      (root.offset, MemoryLayout<() -> UIViewController>.size, MemoryLayout<() -> UIViewController>.alignment)]
        guard writes.allSatisfy({ $0.0 >= 0 && $0.0 % $0.2 == 0 && $0.0 + $0.1 <= MemoryLayout<T>.size }) else { return nil }
        let ranges = writes.map { $0.0..<($0.0 + $0.1) }
        for i in ranges.indices {
            for j in ranges.indices where j > i {
                guard !ranges[i].overlaps(ranges[j]) else { return nil }
            }
        }
        var result = template
        var factoryInstalled = false
        withUnsafeMutablePointer(to: &result) { pointer in
            let base = UnsafeMutableRawPointer(pointer)
            base.advanced(by: writes[0].0).assumingMemoryBound(to: String.self).pointee = id
            base.advanced(by: icon.offset).assumingMemoryBound(to: UIImage.self).pointee = image
            base.advanced(by: selectedIcon.offset).assumingMemoryBound(to: UIImage.self).pointee = selectedImage
            base.advanced(by: label.offset).assumingMemoryBound(to: String.self).pointee = title
            var slot = BHTGlassFactorySlot(factory: factory)
            guard MemoryLayout<BHTGlassFactorySlot>.size == 2 * MemoryLayout<UInt>.size,
                  BHTGlassFieldOffset(BHTGlassFactorySlot.self, index: 0) == 0 else { return }
            withUnsafePointer(to: &slot) { source in
                let bytes = UnsafeRawPointer(source)
                let function = bytes.load(as: UInt.self)
                let context = bytes.load(fromByteOffset: MemoryLayout<UInt>.size, as: UInt.self)
                let destination = base.advanced(by: root.offset)
                let oldContext = destination.load(fromByteOffset: MemoryLayout<UInt>.size, as: UInt.self)
                guard function != 0, context % MemoryLayout<UInt>.alignment == 0,
                      oldContext % MemoryLayout<UInt>.alignment == 0 else { return }
                if let address = UnsafeRawPointer(bitPattern: context) { _ = BHTGlassRetain(address) }
                destination.storeBytes(of: function, as: UInt.self)
                destination.storeBytes(of: context, toByteOffset: MemoryLayout<UInt>.size, as: UInt.self)
                if let address = UnsafeRawPointer(bitPattern: oldContext) { BHTGlassRelease(address) }
                factoryInstalled = true
            }
            withExtendedLifetime(slot) {}
        }
        return factoryInstalled ? result : nil
    }

    @objc(applyToController:account:generation:visiblePages:registry:settingsFactory:likesFactory:)
    public static func apply(to controller: AnyObject, account: AnyObject?, generation: UInt,
                             visiblePages: [String], registry: [[String: Any]],
                             settingsFactory: @escaping () -> UIViewController,
                             likesFactory: @escaping () -> UIViewController) -> [[String: Any]] {
        guard Thread.isMainThread else { return [] }
        #if !BHT_GLASS_TESTS
        guard String(reflecting: type(of: controller)) == "XNavigation.TabBarController" else { return [] }
        #endif
        caches = caches.filter { $0.value.controller != nil }
        let key = ObjectIdentifier(controller)
        let cache = caches[key] ?? BHTGlassCache(controller)
        caches[key] = cache
        guard !cache.applying else { return cache.metadata }
        // Read only the array identity on repeated layout passes. Reflection,
        // cloning and native replacement run only when the input changes.
        if cache.account === account, cache.generation == generation,
           let ivar = class_getInstanceVariable(type(of: controller), "orderedTabs") {
            let offset = ivar_getOffset(ivar)
            if offset >= MemoryLayout<UInt>.size,
               offset + MemoryLayout<UInt>.size <= class_getInstanceSize(type(of: controller)) {
                let storage = Unmanaged.passUnretained(controller).toOpaque().advanced(by: offset).load(as: UInt.self)
                if storage == cache.lastStorage { return cache.metadata }
            }
        }
        guard let current = field(controller, "orderedTabs") else {
            diagnostics["state"] = "nativeArrayUnavailable"; return []
        }
        cache.applying = true
        defer { cache.applying = false }
        if cache.account !== account {
            cache.account = account; cache.originals = nil; cache.accountToken = UUID().uuidString
            cache.generation = 0; cache.lastStorage = 0
        }
        func open<T>(_ value: T) -> [[String: Any]] {
            applyArray(value, controller: controller, cache: cache, generation: generation,
                       visiblePages: visiblePages, registry: registry,
                       settingsFactory: settingsFactory, likesFactory: likesFactory)
        }
        return _openExistential(current, do: open)
    }

    private static func applyArray<T>(_ current: T, controller: AnyObject, cache: BHTGlassCache,
                                      generation: UInt, visiblePages: [String], registry: [[String: Any]],
                                      settingsFactory: @escaping () -> UIViewController,
                                      likesFactory: @escaping () -> UIViewController) -> [[String: Any]] {
        // Open the array's existential, retaining its actual Element type.
        guard let collection = current as? any BHTGlassArray else {
            diagnostics["state"] = "unsupportedNativeArray"; return []
        }
        return collection.applyGlass(controller: controller, cache: cache, generation: generation,
                                     visiblePages: visiblePages, registry: registry,
                                     settingsFactory: settingsFactory, likesFactory: likesFactory)
    }

    fileprivate static func rewrite<Element>(_ current: [Element], controller: AnyObject, cache: BHTGlassCache,
                                             generation: UInt, visiblePages: [String], registry: [[String: Any]],
                                             settingsFactory: @escaping () -> UIViewController,
                                             likesFactory: @escaping () -> UIViewController) -> [[String: Any]] {
        guard !current.isEmpty, current.allSatisfy({ rawID($0) != nil }) else { return [] }
        let currentStorage = withUnsafeBytes(of: current) { $0.load(as: UInt.self) }
        if cache.generation == generation && cache.lastStorage == currentStorage { return cache.metadata }
        let incoming = current.filter { !(rawID($0)?.hasPrefix("nfb.") ?? true) }
        // Keep hidden native descriptors so toggles can restore them. Replace
        // cached values when X supplies fresh descriptors for the same ID.
        var originals = current.contains(where: { rawID($0)?.hasPrefix("nfb.") == true })
            ? cache.originals as? [Element] ?? [] : []
        for tab in incoming {
            if let index = originals.firstIndex(where: { rawID($0) == rawID(tab) }) { originals[index] = tab }
            else { originals.append(tab) }
        }
        guard !originals.isEmpty else { return [] }
        cache.originals = originals
        var metadata: [[String: Any]] = []
        var byPage: [String: Element] = [:]
        var unknown: [Element] = []
        for tab in originals {
            let identifier = rawID(tab)!
            guard let page = canonicalPage(identifier, registry: registry) else { unknown.append(tab); continue }
            byPage[page] = tab
            let imageNames = ["home": "house", "guide": "magnifyingglass", "ntab": "bell", "messages": "envelope",
                              "grok": "sparkles", "communities": "person.2", "profile": "person.crop.circle", "bookmarks": "bookmark"]
            var entry: [String: Any] = ["page": page, "title": field(tab, "accessibilityLabel") as? String ?? page,
                                        "image": "sf:" + (imageNames[page] ?? "square.grid.2x2")]
            if let panel = registry.first(where: { $0["page"] as? String == page })?["panelID"] { entry["panelID"] = panel }
            metadata.append(entry)
        }
        var ordered: [Element] = []
        var placed = Set<String>()
        for page in ["home"] + visiblePages where placed.insert(page).inserted {
            if let tab = byPage[page] { ordered.append(tab) }
        }
        ordered.append(contentsOf: unknown)
        let homeRecognized = byPage["home"] != nil
        if ordered.isEmpty || !homeRecognized { ordered = originals }
        let settingsID = "nfb.settings." + cache.accountToken
        let likesID = "nfb.likes." + cache.accountToken
        let settingsImage = UIImage(systemName: "gearshape")
        let likesImage = UIImage(systemName: "heart")
        let selectedLikesImage = UIImage(systemName: "heart.fill")
        var settingsTab: Element?
        var likesTab: Element?
        if let settingsImage, let likesImage, let selectedLikesImage {
            for template in originals {
                if settingsTab == nil { settingsTab = clone(template, id: settingsID, title: "NeoFreeBird", image: settingsImage,
                                                            selectedImage: settingsImage, factory: settingsFactory) }
                if likesTab == nil && visiblePages.contains("likes") {
                    likesTab = clone(template, id: likesID, title: "Likes", image: likesImage,
                                     selectedImage: selectedLikesImage, factory: likesFactory)
                }
                if settingsTab != nil && (!visiblePages.contains("likes") || likesTab != nil) { break }
            }
        }
        if let likesTab {
            let rank = homeRecognized ? visiblePages.firstIndex(of: "likes") ?? ordered.count : ordered.count
            ordered.insert(likesTab, at: min(rank, ordered.count))
        }
        // Both compact phones and the iPad rail have room for at least five
        // items in this host. Keep settings among those first five.
        if let settingsTab { ordered.insert(settingsTab, at: min(4, ordered.count)) }
        let currentIDs = current.compactMap(rawID)
        let wantedIDs = ordered.compactMap(rawID)
        let nativeSelected = field(controller, "selectedIdentifier").flatMap { field($0, "rawValue") as? String }
        let selected = nativeSelected.flatMap { wantedIDs.contains($0) ? $0 : nil } ?? wantedIDs[0]
        var applied = currentIDs == wantedIDs && cache.generation == generation
        let replacing = !applied
        if !applied { applied = replace(ordered, selecting: selected, on: controller) }
        guard applied else { diagnostics["state"] = "nativeReplaceUnavailable"; return cache.metadata }
        cache.generation = generation
        cache.lastStorage = replacing ? withUnsafeBytes(of: ordered) { $0.load(as: UInt.self) } : currentStorage
        cache.metadata = metadata
        diagnostics = ["state": settingsTab == nil ? "nativeLayoutPreservedSettingsUnavailable" : "installed",
                       "nativePages": originals.compactMap { rawID($0).flatMap { canonicalPage($0, registry: registry) } },
                       "visiblePages": wantedIDs.compactMap { canonicalPage($0, registry: registry) },
                       "unrecognizedNativeCount": unknown.count, "settingsDestinationInstalled": settingsTab != nil,
                       "nativeHomeRecognized": homeRecognized, "customOrderApplied": homeRecognized,
                       "likesDestinationInstalled": likesTab != nil, "concreteDescriptorType": String(reflecting: Element.self)]
        return metadata
    }

    private static func replace<T>(_ array: [T], selecting identifier: String, on object: AnyObject) -> Bool {
        #if BHT_GLASS_TESTS
        return testReplace?(array, identifier, object) ?? false
        #else
        guard MemoryLayout<[T]>.size == MemoryLayout<UInt>.size,
              MemoryLayout<String>.size == 2 * MemoryLayout<UInt>.size,
              let handle = dlopen(nil, RTLD_LAZY), let function = dlsym(handle, replaceSymbol) else { return false }
        defer { dlclose(handle) }
        let word = withUnsafeBytes(of: array) { $0.load(as: UInt.self) }
        withUnsafeBytes(of: identifier) { bytes in
            BHTInvokeGlassReplaceTabs(word, bytes.load(as: UInt.self), bytes.load(fromByteOffset: MemoryLayout<UInt>.size, as: UInt.self),
                                      Unmanaged.passUnretained(object).toOpaque(), function)
        }
        withExtendedLifetime((array, identifier, object)) {}
        return true
        #endif
    }

    @objc public static func diagnosticSnapshot() -> [String: Any] { diagnostics }
}

fileprivate protocol BHTGlassArray {
    func applyGlass(controller: AnyObject, cache: BHTGlassCache, generation: UInt,
                    visiblePages: [String], registry: [[String: Any]],
                    settingsFactory: @escaping () -> UIViewController,
                    likesFactory: @escaping () -> UIViewController) -> [[String: Any]]
}
extension Array: BHTGlassArray {
    fileprivate func applyGlass(controller: AnyObject, cache: BHTGlassCache, generation: UInt,
                                visiblePages: [String], registry: [[String: Any]],
                                settingsFactory: @escaping () -> UIViewController,
                                likesFactory: @escaping () -> UIViewController) -> [[String: Any]] {
        BHTGlassNavigationRuntime.rewrite(self, controller: controller, cache: cache, generation: generation,
                                           visiblePages: visiblePages, registry: registry,
                                           settingsFactory: settingsFactory, likesFactory: likesFactory)
    }
}
