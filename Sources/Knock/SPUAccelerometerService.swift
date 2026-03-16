import Foundation
import IOKit
import IOKit.hid

struct SPUSample: Equatable {
    let x: Double
    let y: Double
    let z: Double
    let timestamp: TimeInterval
}

enum SPUAccelerometerError: LocalizedError {
    case unavailable
    case openFailed(status: kern_return_t)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "AppleSPUHID accelerometer not found on this Mac"
        case .openFailed(let status):
            "Failed to open accelerometer HID device (\(status))"
        }
    }
}

final class SPUAccelerometerService {
    private static let vendorUsagePage = 0xFF00
    private static let accelerometerUsage = 3
    private static let imuReportLength = 22
    private static let imuPayloadOffset = 6
    static let reportBufferSize = 4096
    private static let accelScale = 65536.0

    private static let reportCallback: IOHIDReportWithTimeStampCallback = { context, _, _, _, _, report, reportLength, _ in
        guard let context else { return }
        let service = Unmanaged<SPUAccelerometerService>.fromOpaque(context).takeUnretainedValue()
        service.handleReport(report, length: reportLength)
    }

    var onSample: ((SPUSample) -> Void)?

    private let queue = DispatchQueue(label: "app.tryknock.spu", qos: .userInteractive)
    private var deviceHandles: [DeviceHandle] = []
    private var isRunning = false

    func available() -> Bool {
        !matchingAccelerometerServices().isEmpty
    }

    func start() throws {
        guard !isRunning else { return }

        wakeDrivers()
        let services = matchingAccelerometerServices()
        guard !services.isEmpty else {
            throw SPUAccelerometerError.unavailable
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var openedHandles: [DeviceHandle] = []

        for service in services {
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                IOObjectRelease(service)
                continue
            }

            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                IOObjectRelease(service)
                throw SPUAccelerometerError.openFailed(status: status)
            }

            let handle = DeviceHandle(device: device)
            handle.activate(queue: queue, callback: Self.reportCallback, context: context)
            openedHandles.append(handle)
            IOObjectRelease(service)
        }

        if openedHandles.isEmpty {
            throw SPUAccelerometerError.unavailable
        }

        deviceHandles = openedHandles
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        for handle in deviceHandles {
            handle.stop()
        }
        deviceHandles.removeAll()
        isRunning = false
    }

    private func handleReport(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length == Self.imuReportLength else { return }

        let xRaw = Self.int32LE(report, offset: Self.imuPayloadOffset)
        let yRaw = Self.int32LE(report, offset: Self.imuPayloadOffset + 4)
        let zRaw = Self.int32LE(report, offset: Self.imuPayloadOffset + 8)

        let sample = SPUSample(
            x: Double(xRaw) / Self.accelScale,
            y: Double(yRaw) / Self.accelScale,
            z: Double(zRaw) / Self.accelScale,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        onSample?(sample)
    }

    private func wakeDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }

        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 1000 as CFNumber)
            IOObjectRelease(service)
        }
    }

    private func matchingAccelerometerServices() -> [io_service_t] {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }

        defer { IOObjectRelease(iterator) }

        var matches: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            let usagePage = propertyInt(service, key: "PrimaryUsagePage")
            let usage = propertyInt(service, key: "PrimaryUsage")

            if usagePage == Self.vendorUsagePage, usage == Self.accelerometerUsage {
                matches.append(service)
            } else {
                IOObjectRelease(service)
            }
        }
        return matches
    }

    private func propertyInt(_ service: io_service_t, key: String) -> Int? {
        guard
            let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        else {
            return nil
        }

        return (property as? NSNumber)?.intValue
    }

    private static func int32LE(_ report: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
        let b0 = UInt32(report[offset])
        let b1 = UInt32(report[offset + 1]) << 8
        let b2 = UInt32(report[offset + 2]) << 16
        let b3 = UInt32(report[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }
}

private final class DeviceHandle {
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>

    init(device: IOHIDDevice) {
        self.device = device
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: SPUAccelerometerService.reportBufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    func activate(queue: DispatchQueue, callback: @escaping IOHIDReportWithTimeStampCallback, context: UnsafeMutableRawPointer) {
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device,
            buffer,
            SPUAccelerometerService.reportBufferSize,
            callback,
            context
        )
        IOHIDDeviceActivate(device)
    }

    func stop() {
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}
