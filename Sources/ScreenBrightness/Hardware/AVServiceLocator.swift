import CoreGraphics
import IOKit

/// Finds the DCP AV service (the I2C/DDC endpoint) that belongs to each
/// external CGDisplay on Apple Silicon.
///
/// In the IORegistry each external framebuffer (`IOMobileFramebufferShim`,
/// carrying `DisplayAttributes`) is followed by its `DCPAVServiceProxy`, so we
/// walk the service plane and pair every proxy with the last framebuffer seen.
enum AVServiceLocator {
    struct Candidate {
        let vendor: UInt32
        let product: UInt32
        let serial: UInt32
        let service: io_service_t
    }

    /// Caller owns the returned services and must release them.
    static func candidates() -> [Candidate] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [Candidate] = []
        var lastAttributes: (vendor: UInt32, product: UInt32, serial: UInt32)?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if let attributes = productAttributes(of: entry) {
                lastAttributes = attributes
            }
            if className(of: entry) == "DCPAVServiceProxy",
               stringProperty("Location", of: entry) == "External",
               let attributes = lastAttributes {
                result.append(Candidate(vendor: attributes.vendor, product: attributes.product, serial: attributes.serial, service: entry))
                lastAttributes = nil
                continue // keep the retain for the caller
            }
            IOObjectRelease(entry)
        }
        return result
    }

    /// Picks the candidate for a display: exact serial match first, then the
    /// first unused vendor/product match (identical monitors without serials).
    static func match(_ display: CGDirectDisplayID, in candidates: [Candidate], excluding used: Set<Int>) -> Int? {
        let vendor = CGDisplayVendorNumber(display)
        let product = CGDisplayModelNumber(display)
        let serial = CGDisplaySerialNumber(display)
        let sameModel = candidates.indices.filter {
            !used.contains($0) && candidates[$0].vendor == vendor && candidates[$0].product == product
        }
        return sameModel.first { candidates[$0].serial == serial && serial != 0 } ?? sameModel.first
    }

    private static func productAttributes(of entry: io_registry_entry_t) -> (vendor: UInt32, product: UInt32, serial: UInt32)? {
        guard let attributes = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any],
              let vendorID = product["LegacyManufacturerID"] as? UInt32,
              let productID = product["ProductID"] as? UInt32 else { return nil }
        return (vendorID, productID, product["SerialNumber"] as? UInt32 ?? 0)
    }

    private static func className(of entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buffer)
        return String(cString: buffer)
    }

    private static func stringProperty(_ key: String, of entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}
