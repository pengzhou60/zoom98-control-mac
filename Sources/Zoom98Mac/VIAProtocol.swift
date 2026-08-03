import Foundation

enum LightingChannel: String, CaseIterable, Identifiable {
    case keys = "按键灯"
    case side = "侧边灯条"

    var id: Self { self }

    var valueOffset: UInt8 {
        switch self {
        case .keys: 0x00
        case .side: 0x7F
        }
    }

    func valueID(_ property: LightingProperty) -> UInt8 {
        property.rawValue &+ valueOffset
    }
}

enum LightingProperty: UInt8 {
    case brightness = 0x01
    case effect = 0x02
    case speed = 0x03
    case color = 0x04
}

struct LightingState: Equatable {
    var brightness: UInt8 = 0
    var effect: UInt8 = 0
    var speed: UInt8 = 0
    var hue: UInt8 = 0
    var saturation: UInt8 = 0
}

enum VIACommand {
    static func protocolVersion() -> [UInt8] { [0x01] }

    static func read(_ property: LightingProperty, channel: LightingChannel) -> [UInt8] {
        [0x08, 0x03, channel.valueID(property)]
    }

    static func write(_ property: LightingProperty, value: UInt8, channel: LightingChannel) -> [UInt8] {
        [0x07, 0x03, channel.valueID(property), value]
    }

    static func writeColor(hue: UInt8, saturation: UInt8, channel: LightingChannel) -> [UInt8] {
        [0x07, 0x03, channel.valueID(.color), hue, saturation]
    }

    static func save() -> [UInt8] { [0x09, 0x03] }

    static func readKey(layer: UInt8, row: UInt8, column: UInt8) -> [UInt8] {
        [0x04, layer, row, column]
    }

    static func writeKey(layer: UInt8, row: UInt8, column: UInt8, keycode: UInt16) -> [UInt8] {
        [0x05, layer, row, column, UInt8(keycode >> 8), UInt8(keycode & 0xFF)]
    }

    static func macroCount() -> [UInt8] { [0x0C] }
    static func macroBufferSize() -> [UInt8] { [0x0D] }

    static func readMacroBuffer(offset: UInt16, count: UInt8) -> [UInt8] {
        [0x0E, UInt8(offset >> 8), UInt8(offset & 0xFF), count]
    }

    static func writeMacroBuffer(offset: UInt16, bytes: [UInt8]) -> [UInt8] {
        [0x0F, UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(bytes.count)] + bytes
    }
}

struct KeyboardKey: Identifiable, Codable, Equatable {
    let layer: UInt8
    let row: UInt8
    let column: UInt8
    var keycode: UInt16

    var id: String { "\(layer)-\(row)-\(column)" }
}

struct ExportedConfiguration: Codable {
    let formatVersion: Int?
    let vendorID: Int?
    let productID: Int?
    let protocolVersion: String?
    let createdAt: Date
    let layer: UInt8
    let keys: [KeyboardKey]
    let macros: [String]
    let lighting: LightingStateDTO
}

struct LightingStateDTO: Codable {
    let brightness: UInt8
    let effect: UInt8
    let speed: UInt8
    let hue: UInt8
    let saturation: UInt8

    init(_ state: LightingState) {
        brightness = state.brightness
        effect = state.effect
        speed = state.speed
        hue = state.hue
        saturation = state.saturation
    }
}

enum KeycodeCatalog {
    static let entries: [(UInt16, String)] = {
        var values: [(UInt16, String)] = [(0x0000, "KC_NO"), (0x0001, "KC_TRNS")]
        for (offset, letter) in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").enumerated() {
            values.append((UInt16(0x0004 + offset), "KC_\(letter)"))
        }
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for (offset, digit) in digits.enumerated() {
            values.append((UInt16(0x001E + offset), "KC_\(digit)"))
        }
        values += [
            (0x0028, "KC_ENTER"), (0x0029, "KC_ESC"), (0x002A, "KC_BSPC"),
            (0x002B, "KC_TAB"), (0x002C, "KC_SPACE"), (0x002D, "KC_MINUS"),
            (0x002E, "KC_EQUAL"), (0x002F, "KC_LBRC"), (0x0030, "KC_RBRC"),
            (0x0031, "KC_BSLS"), (0x0033, "KC_SCLN"), (0x0034, "KC_QUOT"),
            (0x0035, "KC_GRV"), (0x0036, "KC_COMM"), (0x0037, "KC_DOT"),
            (0x0038, "KC_SLSH"), (0x0039, "KC_CAPS"),
        ]
        for number in 1...12 { values.append((UInt16(0x0039 + number), "KC_F\(number)")) }
        values += [
            (0x0046, "KC_PSCR"), (0x0047, "KC_SCRL"), (0x0048, "KC_PAUS"),
            (0x0049, "KC_INS"), (0x004A, "KC_HOME"), (0x004B, "KC_PGUP"),
            (0x004C, "KC_DEL"), (0x004D, "KC_END"), (0x004E, "KC_PGDN"),
            (0x004F, "KC_RIGHT"), (0x0050, "KC_LEFT"), (0x0051, "KC_DOWN"),
            (0x0052, "KC_UP"), (0x0053, "KC_NUM"), (0x0054, "KC_PSLS"),
            (0x0055, "KC_PAST"), (0x0056, "KC_PMNS"), (0x0057, "KC_PPLS"),
            (0x0058, "KC_PENT"), (0x0059, "KC_P1"), (0x005A, "KC_P2"),
            (0x005B, "KC_P3"), (0x005C, "KC_P4"), (0x005D, "KC_P5"),
            (0x005E, "KC_P6"), (0x005F, "KC_P7"), (0x0060, "KC_P8"),
            (0x0061, "KC_P9"), (0x0062, "KC_P0"), (0x0063, "KC_PDOT"),
            (0x00E0, "KC_LCTL"), (0x00E1, "KC_LSFT"), (0x00E2, "KC_LALT"),
            (0x00E3, "KC_LGUI"), (0x00E4, "KC_RCTL"), (0x00E5, "KC_RSFT"),
            (0x00E6, "KC_RALT"), (0x00E7, "KC_RGUI"),
            (0x00A8, "KC_MUTE"), (0x00A9, "KC_VOLU"), (0x00AA, "KC_VOLD"),
            (0x00AB, "KC_MNXT"), (0x00AC, "KC_MPRV"), (0x00AD, "KC_MSTP"),
            (0x00AE, "KC_MPLY"), (0x00AF, "KC_MSEL"), (0x00B0, "KC_EJCT"),
            (0x00B1, "KC_MAIL"), (0x00B2, "KC_CALC"), (0x00B3, "KC_MYCM"),
            (0x00B4, "KC_WSCH"), (0x00B5, "KC_WHOM"), (0x00B6, "KC_WBAK"),
            (0x00B7, "KC_WFWD"), (0x00B8, "KC_WSTP"), (0x00B9, "KC_WREF"),
            (0x00BA, "KC_WFAV"), (0x00BB, "KC_MFFD"), (0x00BC, "KC_MRWD"),
            (0x00BD, "KC_BRIU"), (0x00BE, "KC_BRID"),
        ]
        for number in 13...24 { values.append((UInt16(0x0068 + number - 13), "KC_F\(number)")) }
        for index in 0..<16 {
            values.append((UInt16(0x7700 + index), "M\(index)"))
        }
        return values
    }()

    static let names = Dictionary(uniqueKeysWithValues: entries.map { ($0.0, $0.1) })

    static let basicEntries = entries.filter { $0.0 < 0x00A8 || (0x00E0...0x00E7).contains($0.0) }
    static let mediaEntries = entries.filter { (0x00A8...0x00BE).contains($0.0) }
    // QMK exposes several Windows-oriented Consumer/System keycodes that macOS
    // does not bind to an action (for example KC_CALC). Keep them readable when
    // they already exist on the keyboard, but do not offer them as Mac actions.
    static let macSupportedMediaCodes: Set<UInt16> = [
        0x00A8, // mute
        0x00A9, // volume up
        0x00AA, // volume down
        0x00AB, // next track
        0x00AC, // previous track
        0x00AE, // play / pause
        0x00B0, // eject
        0x00BB, // fast-forward
        0x00BC, // rewind
        0x00BD, // brightness up
        0x00BE, // brightness down
    ]
    static let macMediaEntries = mediaEntries.filter { macSupportedMediaCodes.contains($0.0) }
    static let macroEntries = entries.filter { (0x7700...0x770F).contains($0.0) }

    static func isUnsupportedMacMedia(_ code: UInt16) -> Bool {
        (0x00A8...0x00BE).contains(code) && !macSupportedMediaCodes.contains(code)
    }

    static func name(for code: UInt16) -> String {
        names[code] ?? String(format: "0x%04X", code)
    }

    static func displayName(for code: UInt16, macMode: Bool) -> String {
        if ShortcutKeycode.isModified(code) {
            return "不支持 · \(ShortcutKeycode.displayName(code, macMode: macMode))"
        }
        if macMode, isUnsupportedMacMedia(code) {
            return "macOS 不支持 · \(displayName(for: code, macMode: false))"
        }
        if code >= 0x0004, code <= 0x001D {
            return String(UnicodeScalar(Int(code - 0x0004) + 65)!)
        }
        if code >= 0x001E, code <= 0x0027 {
            return ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"][Int(code - 0x001E)]
        }
        if code >= 0x003A, code <= 0x0045 { return "F\(Int(code - 0x003A) + 1)" }
        if code >= 0x0068, code <= 0x0073 { return "F\(Int(code - 0x0068) + 13)" }
        if code >= 0x5220, code <= 0x523F { return "Fn · 按住进入层 \(code & 0x1F)" }

        let common: [UInt16: String] = [
            0x0000: "无功能", 0x0001: "透明 · 继承主键层", 0x0028: "回车",
            0x0029: "Esc", 0x002A: "退格", 0x002B: "Tab", 0x002C: "空格",
            0x002D: "-", 0x002E: "=", 0x002F: "[", 0x0030: "]", 0x0031: "\\",
            0x0033: ";", 0x0034: "'", 0x0035: "`", 0x0036: ",", 0x0037: ".",
            0x0038: "/", 0x0039: "大写锁定", 0x0046: "截屏", 0x0047: "滚动锁定",
            0x0048: "暂停", 0x0049: "插入", 0x004A: "行首", 0x004B: "上一页",
            0x004C: "向前删除", 0x004D: "行尾", 0x004E: "下一页",
            0x004F: "→", 0x0050: "←", 0x0051: "↓", 0x0052: "↑",
            0x0053: "数字锁定", 0x0054: "/", 0x0055: "×", 0x0056: "−",
            0x0057: "+", 0x0058: "回车", 0x0059: "1", 0x005A: "2",
            0x005B: "3", 0x005C: "4", 0x005D: "5", 0x005E: "6",
            0x005F: "7", 0x0060: "8", 0x0061: "9", 0x0062: "0",
            0x0063: ".", 0x00A8: "静音",
            0x00A9: "音量 +", 0x00AA: "音量 −", 0x00AB: "下一首",
            0x00AC: "上一首", 0x00AD: "停止", 0x00AE: "播放 / 暂停",
            0x00AF: "媒体选择", 0x00B0: "弹出", 0x00B1: "邮件",
            0x00B2: "计算器", 0x00B3: "我的电脑", 0x00B4: "网页搜索",
            0x00B5: "浏览器主页", 0x00B6: "浏览器后退", 0x00B7: "浏览器前进",
            0x00B8: "停止加载", 0x00B9: "刷新", 0x00BA: "收藏夹",
            0x00BB: "快进", 0x00BC: "快退", 0x00BD: "屏幕亮度 +",
            0x00BE: "屏幕亮度 −",
        ]
        if let value = common[code] { return value }

        if macMode {
            let macModifiers: [UInt16: String] = [
                0x00E0: "左 Control ⌃", 0x00E1: "左 Shift ⇧",
                0x00E2: "左 Command ⌘", 0x00E3: "左 Option ⌥",
                0x00E4: "右 Control ⌃", 0x00E5: "右 Shift ⇧",
                0x00E6: "右 Command ⌘", 0x00E7: "右 Option ⌥",
            ]
            if let value = macModifiers[code] { return value }
        } else {
            let rawModifiers: [UInt16: String] = [
                0x00E0: "左 Ctrl", 0x00E1: "左 Shift", 0x00E2: "左 Alt",
                0x00E3: "左 Win / GUI", 0x00E4: "右 Ctrl", 0x00E5: "右 Shift",
                0x00E6: "右 Alt", 0x00E7: "右 Win / GUI",
            ]
            if let value = rawModifiers[code] { return value }
        }
        return name(for: code)
    }
}

enum ShortcutKeycode {
    static func isModified(_ code: UInt16) -> Bool {
        let modifiers = (code >> 8) & 0x1F
        return modifiers > 0 && (code & 0x00FF) > 0 && code < 0x2000
    }

    static func displayName(_ code: UInt16, macMode: Bool) -> String {
        let modifiers = (code >> 8) & 0x1F
        var symbols: [String] = []
        if modifiers & 0x01 != 0 { symbols.append("⌃") }
        if modifiers & 0x02 != 0 { symbols.append("⇧") }
        if modifiers & 0x04 != 0 { symbols.append(macMode ? "⌘" : "⌥") }
        if modifiers & 0x08 != 0 { symbols.append(macMode ? "⌥" : "⌘") }
        let base = code & 0x00FF
        return (symbols + [KeycodeCatalog.displayName(for: base, macMode: macMode)]).joined(separator: " ")
    }
}
