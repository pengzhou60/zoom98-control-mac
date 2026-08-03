import Foundation
import IOKit.hid

final class HIDTransport {
    static let vendorID = 0x1EA7
    static let productID = 0xCD68

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
    private var responses: [[UInt8]] = []

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.initialize(repeating: 0, count: 32)
    }

    deinit {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deinitialize(count: 32)
        inputBuffer.deallocate()
    }

    func connect() throws {
        if device != nil { return }
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
            kIOHIDPrimaryUsagePageKey as String: 0xFF60,
            kIOHIDPrimaryUsageKey as String: 0x61,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw HIDError.openManager
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let found = devices.first else {
            throw HIDError.notFound
        }
        guard IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw HIDError.openDevice
        }

        device = found
        IOHIDDeviceScheduleWithRunLoop(found, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            found,
            inputBuffer,
            32,
            { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let transport = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
                transport.responses.append(Array(UnsafeBufferPointer(start: report, count: reportLength)))
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func send(_ command: [UInt8], timeout: TimeInterval = 0.6) throws -> [UInt8] {
        guard let device else { throw HIDError.notFound }
        guard command.count <= 32 else { throw HIDError.commandTooLong }
        responses.removeAll()

        var report = [UInt8](repeating: 0, count: 32)
        report.replaceSubrange(0..<command.count, with: command)
        let result = report.withUnsafeMutableBytes { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                buffer.bindMemory(to: UInt8.self).baseAddress!,
                buffer.count
            )
        }
        guard result == kIOReturnSuccess else { throw HIDError.write(result) }

        let deadline = Date().addingTimeInterval(timeout)
        while responses.isEmpty && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
        guard let response = responses.first else { throw HIDError.timeout }
        return response
    }
}

enum HIDError: LocalizedError {
    case notFound, openManager, openDevice, commandTooLong, timeout
    case write(IOReturn)

    var errorDescription: String? {
        switch self {
        case .notFound: "没有找到 Zoom98 的 USB 配置接口"
        case .openManager: "无法访问 macOS HID 管理器"
        case .openDevice: "无法打开 Zoom98；请检查输入监控权限"
        case .commandTooLong: "VIA 指令超过 32 字节"
        case .timeout: "键盘没有响应"
        case .write(let code): "写入失败（\(code)）"
        }
    }
}
