import CoreGraphics
import Foundation

/// Brightness of the built-in panel (MacBook, iMac) via the private
/// DisplayServices framework, loaded lazily so the app still runs without it.
enum BuiltInDisplay {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func brightness(of id: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func setBrightness(_ value: Double, of id: CGDirectDisplayID) -> Bool {
        setFn?(id, Float(value)) == 0
    }
}
