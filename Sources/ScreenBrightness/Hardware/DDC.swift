import Foundation
import IOKit

// Private IOKit symbols used on Apple Silicon to talk I2C to a display's DCP
// AV service. They are exported by IOKit.framework but not declared in the SDK.
typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

/// Minimal DDC/CI (VESA MCCS) client over an IOAVService.
/// Not thread-safe: callers serialise access (DisplayHardware's queue).
struct DDCChannel {
    static let brightnessVCP: UInt8 = 0x10

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    // Checksum seed: host write address (0x37 << 1) XOR the sub-address.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51
    // Monitors need a pause between a request and its reply / the next command.
    private static let replyDelay: useconds_t = 50_000
    private static let commandGap: useconds_t = 20_000

    private let service: IOAVService

    init?(service entry: io_service_t) {
        guard let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
            return nil
        }
        self.service = service
    }

    /// Returns (current, max) for a VCP code, or nil if the monitor did not answer.
    func read(_ vcp: UInt8, attempts: Int = 4) -> (current: Int, max: Int)? {
        for _ in 0..<attempts {
            guard send([0x01, vcp]) else { continue }
            usleep(Self.replyDelay)
            var reply = [UInt8](repeating: 0, count: 12)
            let status = IOAVServiceReadI2C(service, Self.chipAddress, Self.dataAddress, &reply, UInt32(reply.count))
            // reply: [src, len, 0x02 (VCP reply), result, vcp, type, maxHi, maxLo, curHi, curLo, checksum]
            if status == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp {
                let max = Int(reply[6]) << 8 | Int(reply[7])
                let current = Int(reply[8]) << 8 | Int(reply[9])
                if max > 0 { return (current, max) }
            }
            usleep(Self.commandGap)
        }
        return nil
    }

    @discardableResult
    func write(_ vcp: UInt8, value: Int, attempts: Int = 2) -> Bool {
        let value = UInt16(clamping: value)
        for _ in 0..<attempts {
            if send([0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]) {
                usleep(Self.commandGap)
                return true
            }
            usleep(Self.commandGap)
        }
        return false
    }

    /// Frames a DDC/CI message: length byte, payload, checksum.
    private func send(_ payload: [UInt8]) -> Bool {
        var packet = [0x80 | UInt8(payload.count)] + payload
        packet.append(packet.reduce(Self.checksumSeed, ^))
        let status = IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, &packet, UInt32(packet.count))
        return status == kIOReturnSuccess
    }
}
