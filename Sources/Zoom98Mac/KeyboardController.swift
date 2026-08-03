import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class KeyboardController: ObservableObject {
    @Published var isConnected = false
    @Published var protocolVersion = "—"
    @Published var status = "等待连接"
    @Published var keyState = LightingState()
    @Published var selectedLayer: UInt8 = 0
    @Published var keys: [KeyboardKey] = []
    @Published var macros: [String] = []
    @Published var macroBufferSize = 0
    @Published var isBusy = false
    @Published var editingKey: KeyboardKey?
    @Published var selectedKeycode: UInt16 = 0
    @Published var keycodeSearch = ""
    @Published private(set) var canUndoLastKeyChange = false

    private let transport = HIDTransport()
    private var lastKeyChange: KeyChange?

    var macroUsedBytes: Int {
        macros.reduce(0) { $0 + $1.utf8.count + 1 }
    }

    var macrosAreASCII: Bool {
        macros.allSatisfy { text in
            text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E }
        }
    }

    var macrosFitBuffer: Bool {
        macroBufferSize > 0 && macroUsedBytes <= macroBufferSize
    }

    func connectAndRead() {
        do {
            try transport.connect()
            let version = try transport.send(VIACommand.protocolVersion())
            if version.count >= 3 {
                protocolVersion = String(format: "0x%02X%02X", version[1], version[2])
            }
            keyState = try read(.keys)
            try readMacroMetadata()
            try loadLayer(selectedLayer)
            isConnected = true
            status = "已连接 Zoom98"
        } catch {
            isConnected = false
            status = error.localizedDescription
        }
    }

    func loadLayer(_ layer: UInt8) throws {
        isBusy = true
        defer { isBusy = false }
        var loaded: [KeyboardKey] = []
        for row in UInt8(0)..<UInt8(7) {
            for column in UInt8(0)..<UInt8(17) {
                let response = try transport.send(VIACommand.readKey(layer: layer, row: row, column: column))
                guard response.count >= 6, response[0] == 0x04 else { continue }
                let code = UInt16(response[4]) << 8 | UInt16(response[5])
                loaded.append(KeyboardKey(layer: layer, row: row, column: column, keycode: code))
            }
        }
        selectedLayer = layer
        keys = loaded
        status = "已读取第 \(layer) 层"
    }

    func selectLayer(_ layer: UInt8) {
        do { try loadLayer(layer) } catch { status = error.localizedDescription }
    }

    func setKey(_ key: KeyboardKey, keycode: UInt16) {
        guard key.keycode != keycode else {
            status = "该按键已经是 \(KeycodeCatalog.name(for: keycode))"
            return
        }
        do {
            isBusy = true
            defer { isBusy = false }
            try writeAndVerifyKey(key, keycode: keycode)
            if let index = keys.firstIndex(where: { $0.id == key.id }) {
                keys[index].keycode = keycode
            }
            lastKeyChange = KeyChange(key: key)
            canUndoLastKeyChange = true
            status = "已写入并确认：R\(key.row) C\(key.column) → \(KeycodeCatalog.name(for: keycode))"
        } catch { status = error.localizedDescription }
    }

    func undoLastKeyChange() {
        guard let change = lastKeyChange else { return }
        do {
            isBusy = true
            defer { isBusy = false }
            try writeAndVerifyKey(change.key, keycode: change.key.keycode)
            if let index = keys.firstIndex(where: { $0.id == change.key.id }) {
                keys[index].keycode = change.key.keycode
            }
            lastKeyChange = nil
            canUndoLastKeyChange = false
            status = "已撤销上一次改键，并从键盘读回确认"
        } catch {
            status = "撤销失败：\(error.localizedDescription)"
        }
    }

    func beginEditing(_ key: KeyboardKey) {
        editingKey = key
        selectedKeycode = key.keycode
        keycodeSearch = ""
    }

    func finishEditing(save: Bool) {
        if save, let key = editingKey {
            setKey(key, keycode: selectedKeycode)
        }
        editingKey = nil
    }

    func saveMacros() {
        do {
            isBusy = true
            defer { isBusy = false }
            try writeAndVerifyMacros(macros)
            status = "已保存并校验 \(macros.count) 个文本宏"
        } catch { status = error.localizedDescription }
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Zoom98-layer\(selectedLayer).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let export = ExportedConfiguration(
                formatVersion: 2,
                vendorID: HIDTransport.vendorID,
                productID: HIDTransport.productID,
                protocolVersion: protocolVersion,
                createdAt: Date(), layer: selectedLayer, keys: keys,
                macros: macros, lighting: LightingStateDTO(keyState)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(export).write(to: url, options: .atomic)
            status = "配置已导出"
        } catch { status = error.localizedDescription }
    }

    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(ExportedConfiguration.self, from: Data(contentsOf: url))
            try validateImport(config)
            guard confirmImport(config) else {
                status = "已取消导入，键盘没有变化"
                return
            }
            try performImport(config)
        } catch { status = error.localizedDescription }
    }

    private func readMacroMetadata() throws {
        let countResponse = try transport.send(VIACommand.macroCount())
        let sizeResponse = try transport.send(VIACommand.macroBufferSize())
        let count = Int(countResponse[safe: 1] ?? 0)
        macroBufferSize = Int(sizeResponse[safe: 1] ?? 0) << 8 | Int(sizeResponse[safe: 2] ?? 0)
        let buffer = try readMacroBuffer()
        let segments = buffer.split(separator: 0, omittingEmptySubsequences: false)
        macros = (0..<count).map { index in
            guard index < segments.count else { return "" }
            return String(bytes: segments[index], encoding: .utf8) ?? ""
        }
    }

    private func encodeMacros(_ values: [String]) throws -> [UInt8] {
        var result: [UInt8] = []
        for text in values {
            guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else {
                throw MacroError.asciiOnly
            }
            result += Array(text.utf8)
            result.append(0)
        }
        guard result.count <= macroBufferSize else {
            throw MacroError.tooLarge(result.count, macroBufferSize)
        }
        result += [UInt8](repeating: 0, count: macroBufferSize - result.count)
        return result
    }

    func apply(_ channel: LightingChannel, state: LightingState) {
        do {
            _ = try transport.send(VIACommand.writeColor(hue: state.hue, saturation: state.saturation, channel: channel))
            _ = try transport.send(VIACommand.write(.effect, value: state.effect, channel: channel))
            _ = try transport.send(VIACommand.write(.speed, value: state.speed, channel: channel))
            _ = try transport.send(VIACommand.write(.brightness, value: state.brightness, channel: channel))
            let confirmed = try read(channel)
            setState(confirmed, for: channel)
            status = confirmed == state
                ? "已应用并确认\(channel.rawValue)设置（尚未保存）"
                : "键盘返回的灯光值与请求不同，界面已显示实际值"
        } catch {
            status = error.localizedDescription
        }
    }

    func save() {
        do {
            _ = try transport.send(VIACommand.save())
            status = "灯光设置已保存到键盘"
        } catch {
            status = error.localizedDescription
        }
    }

    private func read(_ channel: LightingChannel) throws -> LightingState {
        let brightness = try transport.send(VIACommand.read(.brightness, channel: channel))
        let effect = try transport.send(VIACommand.read(.effect, channel: channel))
        let speed = try transport.send(VIACommand.read(.speed, channel: channel))
        let color = try transport.send(VIACommand.read(.color, channel: channel))
        return LightingState(
            brightness: brightness[safe: 3] ?? 0,
            effect: effect[safe: 3] ?? 0,
            speed: speed[safe: 3] ?? 0,
            hue: color[safe: 3] ?? 0,
            saturation: color[safe: 4] ?? 0
        )
    }

    private func setState(_ state: LightingState, for channel: LightingChannel) {
        switch channel {
        case .keys: keyState = state
        case .side: break
        }
    }

    private func readKeycode(layer: UInt8, row: UInt8, column: UInt8) throws -> UInt16 {
        let response = try transport.send(VIACommand.readKey(layer: layer, row: row, column: column))
        guard response.count >= 6, response[0] == 0x04 else {
            throw VerificationError.invalidResponse
        }
        return UInt16(response[4]) << 8 | UInt16(response[5])
    }

    private func writeAndVerifyKey(_ key: KeyboardKey, keycode: UInt16) throws {
        _ = try transport.send(
            VIACommand.writeKey(layer: key.layer, row: key.row, column: key.column, keycode: keycode)
        )
        let actual = try readKeycode(layer: key.layer, row: key.row, column: key.column)
        guard actual == keycode else {
            throw VerificationError.keyMismatch(expected: keycode, actual: actual)
        }
    }

    private func readMacroBuffer() throws -> [UInt8] {
        var buffer: [UInt8] = []
        var offset = 0
        while offset < macroBufferSize {
            let length = min(28, macroBufferSize - offset)
            let response = try transport.send(
                VIACommand.readMacroBuffer(offset: UInt16(offset), count: UInt8(length))
            )
            guard response.count >= 4 + length, response[0] == 0x0E else {
                throw VerificationError.invalidResponse
            }
            buffer += response[4..<(4 + length)]
            offset += length
        }
        return buffer
    }

    private func writeAndVerifyMacros(_ values: [String]) throws {
        let bytes = try encodeMacros(values)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 28, bytes.count)
            _ = try transport.send(
                VIACommand.writeMacroBuffer(offset: UInt16(offset), bytes: Array(bytes[offset..<end]))
            )
            offset = end
        }
        let actual = try readMacroBuffer()
        guard actual == bytes else { throw VerificationError.macroMismatch }
    }

    private func validateImport(_ config: ExportedConfiguration) throws {
        if let vendorID = config.vendorID, vendorID != HIDTransport.vendorID {
            throw ImportError.incompatibleDevice
        }
        if let productID = config.productID, productID != HIDTransport.productID {
            throw ImportError.incompatibleDevice
        }
        if let importedProtocol = config.protocolVersion,
           protocolVersion != "—", importedProtocol != protocolVersion {
            throw ImportError.protocolMismatch(importedProtocol, protocolVersion)
        }
        guard config.layer < 4, !config.keys.isEmpty else {
            throw ImportError.invalidLayout
        }
        guard config.keys.allSatisfy({
            $0.layer == config.layer && $0.row < 7 && $0.column < 17
        }) else {
            throw ImportError.invalidLayout
        }
        let uniqueIDs = Set(config.keys.map(\.id))
        guard uniqueIDs.count == config.keys.count else {
            throw ImportError.duplicateKeys
        }
        guard config.macros.count == macros.count else {
            throw ImportError.macroCount(config.macros.count, macros.count)
        }
        _ = try encodeMacros(config.macros)
    }

    private func confirmImport(_ config: ExportedConfiguration) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认导入这份配置？"
        alert.informativeText =
            "将覆盖第 \(config.layer) 层的 \(config.keys.count) 个键位和 \(config.macros.count) 个文本宏。" +
            "写入前会读取当前值；如果中途失败，工具会尝试自动恢复。"
        alert.addButton(withTitle: "导入并校验")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func performImport(_ config: ExportedConfiguration) throws {
        isBusy = true
        defer { isBusy = false }

        let previousMacros = macros
        var previousKeys: [KeyboardKey] = []
        for key in config.keys {
            let previous = try readKeycode(layer: key.layer, row: key.row, column: key.column)
            previousKeys.append(
                KeyboardKey(layer: key.layer, row: key.row, column: key.column, keycode: previous)
            )
        }

        do {
            for key in config.keys {
                try writeAndVerifyKey(key, keycode: key.keycode)
            }
            try writeAndVerifyMacros(config.macros)
            macros = config.macros
            try loadLayer(config.layer)
            lastKeyChange = nil
            canUndoLastKeyChange = false
            status = "配置已导入；所有键位和文本宏均已读回校验"
        } catch {
            var rollbackFailure: Error?
            do {
                for key in previousKeys {
                    try writeAndVerifyKey(key, keycode: key.keycode)
                }
                try writeAndVerifyMacros(previousMacros)
                macros = previousMacros
                try loadLayer(config.layer)
            } catch {
                rollbackFailure = error
            }
            if let rollbackFailure {
                throw ImportError.rollbackFailed(original: error, rollback: rollbackFailure)
            }
            throw ImportError.importFailedAndRestored(error)
        }
    }
}

private struct KeyChange {
    let key: KeyboardKey
}

enum VerificationError: LocalizedError {
    case invalidResponse
    case keyMismatch(expected: UInt16, actual: UInt16)
    case macroMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "键盘返回了无法识别的 VIA 响应"
        case .keyMismatch(let expected, let actual):
            "写入后校验失败：请求 \(KeycodeCatalog.name(for: expected))，实际读回 \(KeycodeCatalog.name(for: actual))"
        case .macroMismatch:
            "文本宏写入后读回内容不一致"
        }
    }
}

enum ImportError: LocalizedError {
    case incompatibleDevice
    case protocolMismatch(String, String)
    case invalidLayout
    case duplicateKeys
    case macroCount(Int, Int)
    case importFailedAndRestored(Error)
    case rollbackFailed(original: Error, rollback: Error)

    var errorDescription: String? {
        switch self {
        case .incompatibleDevice:
            "配置文件来自不同型号的键盘，已阻止导入"
        case .protocolMismatch(let imported, let current):
            "VIA 协议版本不一致（文件 \(imported)，当前键盘 \(current)）"
        case .invalidLayout:
            "配置文件的层或矩阵坐标无效"
        case .duplicateKeys:
            "配置文件包含重复键位，已阻止导入"
        case .macroCount(let imported, let current):
            "宏数量不兼容（文件 \(imported)，当前键盘 \(current)）"
        case .importFailedAndRestored(let error):
            "导入失败，原配置已恢复：\(error.localizedDescription)"
        case .rollbackFailed(let original, let rollback):
            "导入失败且自动恢复未完成。原错误：\(original.localizedDescription)；恢复错误：\(rollback.localizedDescription)"
        }
    }
}

enum MacroError: LocalizedError {
    case asciiOnly
    case tooLarge(Int, Int)

    var errorDescription: String? {
        switch self {
        case .asciiOnly: "当前固件的文本宏仅支持 ASCII 字符"
        case .tooLarge(let used, let limit): "宏数据需要 \(used) 字节，超过 \(limit) 字节容量"
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
