import Combine
@preconcurrency import CoreBluetooth
import Foundation

struct BLEDeviceItem: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var advertisedServices: [String]

    var id: UUID { peripheral.identifier }
}

private enum BLEConnectionRole {
    case screen
    case battery
    case inspection
}

@MainActor
final class BLEController: NSObject, ObservableObject {
    @Published var status = "等待蓝牙初始化"
    @Published var devices: [BLEDeviceItem] = []
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectedName = "—"
    @Published var batteryText = "—"
    @Published var batterySourceText = "未连接键盘电量服务"
    @Published var firmwareText = "—"
    @Published var nameInspectionText = "尚未检查"
    @Published var requestedBluetoothName = "Zoom98"
    @Published var canWriteDeviceName = false
    @Published var screenStyleIndex = 0
    @Published var clockStyleIndex = 0
    @Published var logLines: [String] = []

    private static let serviceUUID = CBUUID(string: "1F40EAF8-AAB4-14A3-F1BA-F61F35CDDBAA")
    private static let writeUUID = CBUUID(string: "1F400001-AAB4-14A3-F1BA-F61F35CDDBAA")
    private static let notifyUUID = CBUUID(string: "1F400002-AAB4-14A3-F1BA-F61F35CDDBAA")
    private static let bulkUUID = CBUUID(string: "1F400003-AAB4-14A3-F1BA-F61F35CDDBAA")
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryUUID = CBUUID(string: "2A19")
    private static let hidServiceUUID = CBUUID(string: "1812")
    private static let deviceInformationServiceUUID = CBUUID(string: "180A")
    private static let genericAccessServiceUUID = CBUUID(string: "1800")
    private static let deviceNameUUID = CBUUID(string: "2A00")

    private var central: CBCentralManager!
    private var screenPeripheral: CBPeripheral?
    private var batteryPeripheral: CBPeripheral?
    private var inspectionPeripheral: CBPeripheral?
    private var deviceNameCharacteristic: CBCharacteristic?
    private var connectionRoles: [UUID: BLEConnectionRole] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var bulkCharacteristic: CBCharacteristic?
    private var pendingCommandName = ""
    private var privateBatteryRequestID: UUID?
    private var standardBatteryRequestID: UUID?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = stateDescription(central.state)
            return
        }
        devices.removeAll()
        isScanning = true
        status = "正在扫描键盘、鼠标与 Zoom98 屏幕…"
        appendLog("SCAN start (HID + Zoom98 Screen filter)")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        let connectedHID = central.retrieveConnectedPeripherals(withServices: [Self.hidServiceUUID])
        appendLog("CONNECTED HID devices: \(connectedHID.map { $0.name ?? "未命名设备" }.joined(separator: ", "))")
        for peripheral in connectedHID {
            let name = peripheral.name ?? "未命名的已连接 HID"
            let item = BLEDeviceItem(peripheral: peripheral, name: name, rssi: 0, advertisedServices: ["1812", "SYSTEM-CONNECTED"])
            if let index = devices.firstIndex(where: { $0.id == item.id }) {
                devices[index] = item
            } else {
                devices.insert(item, at: 0)
            }
        }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        if !isConnected { status = "扫描已停止，共发现 \(devices.count) 个设备" }
    }

    func connect(_ device: BLEDeviceItem) {
        stopScan()
        status = "正在连接 \(device.name)…"
        appendLog("CONNECT \(device.name) [\(device.id.uuidString)]")
        screenPeripheral = device.peripheral
        connectionRoles[device.id] = .screen
        device.peripheral.delegate = self
        central.connect(device.peripheral)
    }

    func connectForBattery(_ device: BLEDeviceItem) {
        let requestID = UUID()
        standardBatteryRequestID = requestID
        batterySourceText = "正在连接 \(device.name)…"
        appendLog("BATTERY CONNECT \(device.name) [\(device.id.uuidString)]")
        batteryPeripheral = device.peripheral
        connectionRoles[device.id] = .battery
        device.peripheral.delegate = self
        central.connect(device.peripheral)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.standardBatteryRequestID == requestID else { return }
            self.standardBatteryRequestID = nil
            self.batterySourceText = "读取超时；该 HID 设备可能没有公开标准电量服务"
            self.appendLog("BATTERY timeout \(device.name)")
        }
    }

    func inspectLikelyKeyboardController() {
        let connectedHID = central.retrieveConnectedPeripherals(withServices: [Self.hidServiceUUID]).filter {
            $0.identifier != screenPeripheral?.identifier &&
            !($0.name?.localizedCaseInsensitiveContains("Zoom98 Screen") ?? false)
        }
        for peripheral in connectedHID {
            let item = BLEDeviceItem(peripheral: peripheral,
                                     name: peripheral.name ?? "未命名的已连接 HID",
                                     rssi: 0,
                                     advertisedServices: ["1812", "SYSTEM-CONNECTED"])
            if let index = devices.firstIndex(where: { $0.id == item.id }) {
                devices[index] = item
            } else {
                devices.insert(item, at: 0)
            }
        }
        guard !connectedHID.isEmpty else {
            status = "macOS 没有返回已连接的 HID 键盘；Zoom98 Screen 不是键盘主控"
            appendLog("KEYBOARD HID not found; screen excluded")
            return
        }
        if connectedHID.count == 1, let peripheral = connectedHID.first,
           let device = devices.first(where: { $0.id == peripheral.identifier }) {
            status = "发现 1 个已连接 HID，正在读取它的标准电量服务"
            connectForBattery(device)
        } else {
            status = "发现 \(connectedHID.count) 个已连接 HID；请在左侧对目标键盘点“读电量”"
            appendLog("CONNECTED HID candidates: \(connectedHID.map { $0.name ?? "未命名设备" }.joined(separator: ", "))")
        }
    }

    func inspectNameSupport(_ device: BLEDeviceItem) {
        canWriteDeviceName = false
        deviceNameCharacteristic = nil
        nameInspectionText = "正在检查 \(device.name)…"
        appendLog("NAME INSPECT CONNECT \(device.name) [\(device.id.uuidString)]")
        inspectionPeripheral = device.peripheral
        connectionRoles[device.id] = .inspection
        device.peripheral.delegate = self
        if device.peripheral.state == .connected {
            nameInspectionText = "正在复用已有连接，检查 \(device.name) 的全部 GATT 服务…"
            appendLog("NAME INSPECT reuse existing connection")
            device.peripheral.discoverServices(nil)
        } else {
            central.connect(device.peripheral)
        }
    }

    func writeBluetoothName() {
        let name = requestedBluetoothName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 29 else {
            nameInspectionText = "名称需要为 1–29 个 UTF-8 字节"
            return
        }
        guard let peripheral = inspectionPeripheral,
              let characteristic = deviceNameCharacteristic,
              canWriteDeviceName else {
            nameInspectionText = "设备名称特征不可写，已阻止发送"
            return
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        pendingCommandName = "修改蓝牙名称"
        peripheral.writeValue(Data(name.utf8), for: characteristic, type: type)
        appendLog("DEVICE NAME TX utf8=\(name)")
        if type == .withoutResponse {
            nameInspectionText = "名称已发送；键盘可能需要重启并在 macOS 中忽略后重新配对"
        }
    }

    func disconnect() {
        guard let screenPeripheral else { return }
        central.cancelPeripheralConnection(screenPeripheral)
    }

    func readDeviceInfo() {
        send(payload: [0x00, 0x01, 0x00], name: "读取固件版本")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.send(payload: [0x00, 0x13, 0x00], name: "读取键盘状态")
        }
    }

    func readKeyboardBattery() {
        // Pocket Wuque: KeyBoardConstant.getSysData() == { 0x00, 0x17 }.
        // Its 0x18 response carries the keyboard battery percentage at byte 25.
        let requestID = UUID()
        privateBatteryRequestID = requestID
        send(payload: [0x00, 0x17], name: "读取键盘系统信息与电量")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.privateBatteryRequestID == requestID else { return }
            self.privateBatteryRequestID = nil
            self.status = "屏幕模块未返回键盘电量；请改用左侧 HID 设备的“读电量”"
            self.batterySourceText = "Zoom98 Screen 不提供稳定的键盘电量响应"
            self.appendLog("PRIVATE BATTERY timeout; no 0x18 response")
        }
    }

    func syncTime() {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = parts.year ?? 2026
        send(payload: [
            0x04, 0x01, UInt8((year >> 8) & 0xFF), UInt8(year & 0xFF),
            UInt8(parts.month ?? 1), UInt8(parts.day ?? 1), UInt8(parts.hour ?? 0),
            UInt8(parts.minute ?? 0), UInt8(parts.second ?? 0),
        ], name: "同步时间")
    }

    func applyScreenStyle() {
        send(payload: [0x04, 0x0D, 0x00, UInt8(clamping: screenStyleIndex + 1)], name: "切换屏幕样式")
    }

    func applyClockStyle() {
        send(payload: [0x04, 0x0D, UInt8(clamping: clockStyleIndex + 1), 0x00], name: "切换时钟样式")
    }

    private func send(payload: [UInt8], name: String) {
        guard let peripheral = screenPeripheral, let characteristic = writeCharacteristic else {
            status = "配置服务尚未就绪"
            appendLog("TX blocked: \(name), write characteristic unavailable")
            return
        }
        let packet = Self.wrap(payload)
        pendingCommandName = name
        appendLog("TX \(name): \(Self.hex(packet))")
        peripheral.writeValue(Data(packet), for: characteristic, type: .withResponse)
    }

    private static func wrap(_ payload: [UInt8]) -> [UInt8] {
        let length = UInt32(payload.count)
        let checksum = payload.reduce(UInt8(0), ^)
        return [
            0x88, 0x00, 0x00,
            UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF), checksum,
        ] + payload
    }

    private func appendLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("\(stamp)  \(line)")
        if logLines.count > 100 { logLines.removeFirst(logLines.count - 100) }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "蓝牙已开启"
        case .poweredOff: "蓝牙已关闭"
        case .unauthorized: "Zoom98 Control 没有蓝牙权限"
        case .unsupported: "这台 Mac 不支持蓝牙低功耗"
        case .resetting: "蓝牙正在重置"
        case .unknown: "蓝牙状态未知"
        @unknown default: "未知蓝牙状态"
        }
    }
}

extension BLEController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status = stateDescription(central.state)
        appendLog("Bluetooth: \(status)")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "未命名设备"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let isHID = services.contains(Self.hidServiceUUID.uuidString)
        let isZoomScreen = services.contains(Self.serviceUUID.uuidString)
        let isNamedZoom = name.localizedCaseInsensitiveContains("Zoom98") || name.localizedCaseInsensitiveContains("Zoom 98")
        guard isHID || isZoomScreen || isNamedZoom else { return }
        let item = BLEDeviceItem(peripheral: peripheral, name: name, rssi: RSSI.intValue, advertisedServices: services)
        if let index = devices.firstIndex(where: { $0.id == item.id }) {
            devices[index] = item
        } else {
            devices.append(item)
            devices.sort { $0.rssi > $1.rssi }
            appendLog("FOUND \(name), RSSI \(RSSI), services \(services.joined(separator: ","))")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let discoveredName = peripheral.name ?? devices.first(where: { $0.id == peripheral.identifier })?.name ?? "未命名设备"
        switch connectionRoles[peripheral.identifier] {
        case .battery:
            batterySourceText = "已连接 \(discoveredName)，正在读取…"
            appendLog("BATTERY CONNECTED \(discoveredName)")
            peripheral.discoverServices([Self.batteryServiceUUID])
        case .inspection:
            nameInspectionText = "已连接 \(discoveredName)，正在检查全部 GATT 服务…"
            appendLog("NAME INSPECT CONNECTED \(discoveredName)")
            peripheral.discoverServices(nil)
        case .screen, .none:
            isConnected = true
            connectedName = discoveredName
            status = "已连接 \(connectedName)，正在发现服务…"
            appendLog("CONNECTED \(connectedName)")
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if connectionRoles[peripheral.identifier] == .battery {
            standardBatteryRequestID = nil
            batterySourceText = "电量服务连接失败"
            appendLog("BATTERY CONNECT failed: \(error?.localizedDescription ?? "未知错误")")
        } else if connectionRoles[peripheral.identifier] == .inspection {
            nameInspectionText = "检查连接失败：\(error?.localizedDescription ?? "未知错误")"
            appendLog("NAME INSPECT CONNECT failed: \(error?.localizedDescription ?? "未知错误")")
        } else {
            status = "连接失败：\(error?.localizedDescription ?? "未知错误")"
            appendLog("CONNECT failed: \(status)")
            isConnected = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if connectionRoles[peripheral.identifier] == .battery {
            standardBatteryRequestID = nil
            batterySourceText = "键盘电量服务已断开"
            appendLog("BATTERY DISCONNECTED")
            batteryPeripheral = nil
        } else if connectionRoles[peripheral.identifier] == .inspection {
            appendLog("NAME INSPECT DISCONNECTED")
            inspectionPeripheral = nil
        } else {
            status = error == nil ? "BLE 已断开" : "BLE 断开：\(error!.localizedDescription)"
            appendLog("DISCONNECTED \(status)")
            isConnected = false
            connectedName = "—"
            screenPeripheral = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            bulkCharacteristic = nil
        }
        connectionRoles[peripheral.identifier] = nil
    }
}

extension BLEController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            status = "服务发现失败：\(error.localizedDescription)"
            return
        }
        for service in peripheral.services ?? [] {
            appendLog("SERVICE \(service.uuid.uuidString)")
            if connectionRoles[peripheral.identifier] == .inspection {
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == Self.serviceUUID {
                peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID, Self.bulkUUID], for: service)
            } else if service.uuid == Self.batteryServiceUUID {
                peripheral.discoverCharacteristics([Self.batteryUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            status = "特征发现失败：\(error.localizedDescription)"
            return
        }
        for characteristic in service.characteristics ?? [] {
            let properties = Self.describe(characteristic.properties)
            appendLog("CHAR \(characteristic.uuid.uuidString) properties=\(properties)")
            if connectionRoles[peripheral.identifier] == .inspection,
               characteristic.uuid == Self.deviceNameUUID {
                let writable = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
                deviceNameCharacteristic = characteristic
                canWriteDeviceName = writable
                nameInspectionText = writable
                    ? "发现 Device Name (2A00)，并且可写；具备真实改名条件"
                    : "发现 Device Name (2A00)，但它是只读的；不能通过标准 GATT 改名"
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
            if connectionRoles[peripheral.identifier] == .inspection,
               service.uuid == Self.deviceInformationServiceUUID,
               characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            switch characteristic.uuid {
            case Self.writeUUID:
                writeCharacteristic = characteristic
            case Self.notifyUUID:
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.bulkUUID:
                bulkCharacteristic = characteristic
            case Self.batteryUUID:
                peripheral.readValue(for: characteristic)
            default: break
            }
        }
        if connectionRoles[peripheral.identifier] == .inspection {
            let allServicesComplete = peripheral.services?.allSatisfy { $0.characteristics != nil } == true
            let hasDeviceName = peripheral.services?.contains(where: {
                $0.characteristics?.contains(where: { $0.uuid == Self.deviceNameUUID }) == true
            }) == true
            if allServicesComplete, !hasDeviceName {
                nameInspectionText = "未暴露 Device Name (2A00)；标准蓝牙改名不可用，仍可能存在厂商私有命令"
                appendLog("NAME INSPECT RESULT: 2A00 not exposed")
            }
        }
        if writeCharacteristic != nil, notifyCharacteristic != nil {
            status = "BLE 配置通道已就绪"
            appendLog("READY command + notification characteristics")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.readDeviceInfo() }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        appendLog(error == nil ? "NOTIFY enabled \(characteristic.uuid.uuidString)" : "NOTIFY failed: \(error!.localizedDescription)")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = "\(pendingCommandName)写入失败：\(error.localizedDescription)"
            appendLog("WRITE failed: \(error.localizedDescription)")
        } else {
            status = "\(pendingCommandName)已发送，等待键盘响应"
            appendLog("WRITE accepted by macOS")
            if characteristic.uuid == Self.deviceNameUUID {
                nameInspectionText = "名称写入已被设备接受；请重启键盘，必要时忽略设备后重新配对"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("RX failed: \(error.localizedDescription)")
            return
        }
        let bytes = [UInt8](characteristic.value ?? Data())
        if characteristic.uuid == Self.deviceNameUUID {
            let currentName = String(data: characteristic.value ?? Data(), encoding: .utf8) ?? Self.hex(bytes)
            appendLog("DEVICE NAME value=\(currentName)")
            return
        }
        if characteristic.service?.uuid == Self.deviceInformationServiceUUID {
            let value = String(data: characteristic.value ?? Data(), encoding: .utf8) ?? Self.hex(bytes)
            appendLog("DEVICE INFO \(characteristic.uuid.uuidString)=\(value)")
            return
        }
        if characteristic.uuid == Self.batteryUUID, let value = bytes.first {
            standardBatteryRequestID = nil
            batteryText = "\(value)%"
            batterySourceText = peripheral.name ?? devices.first(where: { $0.id == peripheral.identifier })?.name ?? "键盘主控制器"
            appendLog("BATTERY \(value)%")
            return
        }
        appendLog("RX \(Self.hex(bytes))")
        if bytes.count > 25, bytes[9] == 0x18 {
            privateBatteryRequestID = nil
            let value = bytes[25]
            batteryText = "\(value)%"
            batterySourceText = "Zoom98 私有系统信息（屏幕配置通道）"
            appendLog("PARSED Zoom98 keyboard battery \(value)%")
        } else if bytes.count > 14, bytes[9] == 0x02 {
            firmwareText = "V\(bytes[12]).\(bytes[13]).\(bytes[14])"
            appendLog("PARSED firmware \(firmwareText), hardware 0x\(String(format: "%02X%02X", bytes[10], bytes[11]))")
        } else if bytes.count == 14, bytes[9] == 0x14 {
            appendLog("PARSED keyboard status code \(bytes[13])")
        }
        status = "收到键盘响应（\(bytes.count) 字节）"
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if names.isEmpty { names.append("raw=\(properties.rawValue)") }
        return names.joined(separator: ",")
    }
}
