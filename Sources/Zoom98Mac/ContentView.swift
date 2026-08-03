import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: KeyboardController
    @ObservedObject var bleController: BLEController

    var body: some View {
        VStack(spacing: 20) {
            header
            TabView {
                lightingPage
                    .tabItem { Label("灯光", systemImage: "lightbulb") }
                KeymapPage(controller: controller)
                    .tabItem { Label("键位", systemImage: "keyboard") }
                MacroPage(controller: controller)
                    .tabItem { Label("文本宏", systemImage: "text.badge.plus") }
                BLEScreenPage(controller: bleController)
                    .tabItem { Label("设备与屏幕", systemImage: "display") }
            }
            footer
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { controller.connectAndRead() }
    }

    private var lightingPage: some View {
        HStack(alignment: .top, spacing: 16) {
            LightingCard(
                channel: .keys,
                state: $controller.keyState,
                enabled: controller.isConnected,
                apply: controller.apply,
                save: controller.save
            )
            BottomLightInfoCard()
        }
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Zoom98 Control")
                    .font(.title2.weight(.semibold))
                Text("USB · VIA \(controller.protocolVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(controller.isConnected ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(controller.status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("重新读取") { controller.connectAndRead() }
            Menu {
                Button("导出当前配置…") { controller.exportConfiguration() }
                Button("导入配置…") { controller.importConfiguration() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("改键与文本宏直接写入键盘，不需要工具常驻；灯光请在灯光页单独保存", systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct BLEScreenPage: View {
    @ObservedObject var controller: BLEController
    @AppStorage("showBLEDiagnostics") private var showDiagnostics = false

    private let screenService = "1F40EAF8-AAB4-14A3-F1BA-F61F35CDDBAA"

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            GroupBox("键盘、鼠标与屏幕") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(controller.isScanning ? "停止扫描" : "开始扫描") {
                            controller.isScanning ? controller.stopScan() : controller.startScan()
                        }
                        .buttonStyle(.borderedProminent)
                        if controller.isScanning { ProgressView().controlSize(.small) }
                        Button("查找已连接键盘") { controller.inspectLikelyKeyboardController() }
                        Spacer()
                        Text("按信号强度排序").font(.caption).foregroundStyle(.secondary)
                    }
                    List(controller.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: device.advertisedServices.contains(screenService) ? "display" : "keyboard")
                                        .foregroundStyle(.secondary)
                                    Text(device.name).font(.headline)
                                }
                                Text(device.id.uuidString)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if !device.advertisedServices.isEmpty {
                                    Text(device.advertisedServices.joined(separator: ", "))
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(device.advertisedServices.contains("FFF0") ? .orange : .secondary)
                                }
                            }
                            Spacer()
                            if device.rssi != 0 {
                                Text("\(device.rssi) dBm").font(.caption).monospacedDigit()
                            } else {
                                Text("系统已连接").font(.caption).foregroundStyle(.green)
                            }
                            if device.advertisedServices.contains("1812") || device.advertisedServices.contains("SYSTEM-CONNECTED") {
                                Button("读电量") { controller.connectForBattery(device) }
                            }
                            if device.advertisedServices.contains(screenService) {
                                Button("连接屏幕") { controller.connect(device) }
                            }
                        }
                    }
                    Text("这里只显示 HID 键盘/鼠标和 Zoom98 Screen；扫描与读取都由你手动触发，不会在后台运行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 14) {
                GroupBox("Zoom98 状态与屏幕") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("状态", value: controller.status)
                        LabeledContent("设备", value: controller.connectedName)
                        LabeledContent("固件", value: controller.firmwareText)
                        LabeledContent("电量", value: controller.batteryText)
                        LabeledContent("电量来源", value: controller.batterySourceText)
                        Divider()
                        HStack {
                            Button("重新读取") { controller.readDeviceInfo() }
                            Button("读取键盘电量") { controller.readKeyboardBattery() }
                            Button("同步 Mac 时间") { controller.syncTime() }
                            Spacer()
                            Button("断开") { controller.disconnect() }
                        }
                        .disabled(!controller.isConnected)
                        HStack {
                            Stepper("屏幕样式 \(controller.screenStyleIndex + 1)", value: $controller.screenStyleIndex, in: 0...3)
                            Button("应用") { controller.applyScreenStyle() }
                        }
                        .disabled(!controller.isConnected)
                        HStack {
                            Stepper("时钟样式 \(controller.clockStyleIndex + 1)", value: $controller.clockStyleIndex, in: 0...3)
                            Button("应用") { controller.applyClockStyle() }
                        }
                        .disabled(!controller.isConnected)
                    }
                    .padding(8)
                }

                DisclosureGroup("诊断信息", isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("蓝牙名称能力：\(controller.nameInspectionText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        ScrollView([.vertical, .horizontal]) {
                            Text(controller.logLines.joined(separator: "\n"))
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(height: 155)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(8)
                }
                .padding(.horizontal, 4)
                .frame(height: showDiagnostics ? 225 : 28, alignment: .top)
                .clipped()
                Spacer(minLength: 0)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 10)
    }
}

private struct KeymapPage: View {
    @ObservedObject var controller: KeyboardController
    @AppStorage("showMacEffectiveKeyLabels") private var showMacEffectiveLabels = true
    @AppStorage("showPhysicalKeyLayout") private var showPhysicalLayout = true

    private let columns = Array(repeating: GridItem(.fixed(62), spacing: 5), count: 17)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showPhysicalLayout ? "功能层" : "矩阵层")
                Picker("", selection: Binding(
                    get: { controller.selectedLayer },
                    set: { controller.selectLayer($0) }
                )) {
                    if showPhysicalLayout {
                        Text("主键层").tag(UInt8(0))
                        Text("Fn 层").tag(UInt8(1))
                    } else {
                        ForEach(UInt8(0)..<UInt8(4), id: \.self) { Text("层 \($0)").tag($0) }
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: showPhysicalLayout ? 190 : 260)
                .labelsHidden()
                Toggle("按 Mac 模式显示实际功能", isOn: $showMacEffectiveLabels)
                    .toggleStyle(.switch)
                Picker("视图", selection: $showPhysicalLayout) {
                    Text("实体布局").tag(true)
                    Text("高级矩阵").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .onChange(of: showPhysicalLayout) { _, physical in
                    if physical, controller.selectedLayer > 1 { controller.selectLayer(0) }
                }
                Spacer()
                if controller.isBusy { ProgressView().controlSize(.small) }
                Button("撤销改键", systemImage: "arrow.uturn.backward") {
                    controller.undoLastKeyChange()
                }
                .disabled(!controller.canUndoLastKeyChange || controller.isBusy)
                Text("显示模式不会写入键盘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            modifierGuide
            if showPhysicalLayout {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Zoom98PhysicalKeymapView(
                            keys: controller.keys,
                            macMode: showMacEffectiveLabels,
                            availableWidth: geometry.size.width,
                            edit: controller.beginEditing
                        )
                        .frame(minWidth: geometry.size.width, alignment: .center)
                        .padding(.vertical, 8)
                    }
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(controller.keys) { key in
                            Button {
                                controller.beginEditing(key)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(KeycodeCatalog.displayName(for: key.keycode, macMode: showMacEffectiveLabels))
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("\(KeycodeCatalog.name(for: key.keycode)) · \(key.row),\(key.column)")
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 56, height: 38)
                            }
                            .buttonStyle(.bordered)
                            .tint(key.keycode == 0 ? .gray.opacity(0.35) : .accentColor)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(.top, 10)
        .sheet(item: $controller.editingKey) { key in
            KeyEditorSheet(controller: controller, key: key)
        }
    }

    private var modifierGuide: some View {
        let coordinates: [(UInt8, UInt8)] = [(5, 0), (5, 1), (5, 2), (5, 6), (5, 7), (5, 8)]
        return GroupBox("底排修饰键 · 当前层") {
            HStack(spacing: 8) {
                ForEach(Array(coordinates.enumerated()), id: \.offset) { _, coordinate in
                    if let key = controller.keys.first(where: { $0.row == coordinate.0 && $0.column == coordinate.1 }) {
                        VStack(spacing: 2) {
                            Text(KeycodeCatalog.displayName(for: key.keycode, macMode: showMacEffectiveLabels))
                                .font(.caption.weight(.semibold))
                            Text("\(KeycodeCatalog.name(for: key.keycode)) · \(coordinate.0),\(coordinate.1)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct PhysicalKeySpec: Identifiable {
    let row: UInt8
    let column: UInt8
    let x: CGFloat
    let y: CGFloat
    var width: CGFloat = 1
    var height: CGFloat = 1

    var id: String { "\(row)-\(column)" }
}

private struct Zoom98PhysicalKeymapView: View {
    let keys: [KeyboardKey]
    let macMode: Bool
    let availableWidth: CGFloat
    let edit: (KeyboardKey) -> Void

    private let gap: CGFloat = 3
    private var unit: CGFloat {
        let horizontalInsets: CGFloat = 32
        let fitted = (availableWidth - horizontalInsets) / 22 - gap
        return min(48, max(30, fitted))
    }

    static let specs: [PhysicalKeySpec] = [
        // Function row: F13, screen, then four independent keys above the numpad.
        .init(row: 0, column: 0, x: 0, y: 0),
        .init(row: 0, column: 1, x: 1.5, y: 0), .init(row: 0, column: 2, x: 2.5, y: 0),
        .init(row: 0, column: 3, x: 3.5, y: 0), .init(row: 0, column: 4, x: 4.5, y: 0),
        .init(row: 0, column: 5, x: 5.75, y: 0), .init(row: 0, column: 6, x: 6.75, y: 0),
        .init(row: 0, column: 7, x: 7.75, y: 0), .init(row: 0, column: 8, x: 8.75, y: 0),
        .init(row: 0, column: 9, x: 10, y: 0), .init(row: 0, column: 10, x: 11, y: 0),
        .init(row: 0, column: 11, x: 12, y: 0), .init(row: 6, column: 2, x: 13, y: 0),
        .init(row: 6, column: 3, x: 14.25, y: 0),
        .init(row: 0, column: 12, x: 18, y: 0), .init(row: 0, column: 13, x: 19, y: 0),
        .init(row: 0, column: 14, x: 20, y: 0), .init(row: 0, column: 15, x: 21, y: 0),

        // Number row.
        .init(row: 1, column: 0, x: 0, y: 1.25),
        .init(row: 1, column: 1, x: 1, y: 1.25), .init(row: 1, column: 2, x: 2, y: 1.25),
        .init(row: 1, column: 3, x: 3, y: 1.25), .init(row: 1, column: 4, x: 4, y: 1.25),
        .init(row: 1, column: 5, x: 5, y: 1.25), .init(row: 1, column: 6, x: 6, y: 1.25),
        .init(row: 1, column: 7, x: 7, y: 1.25), .init(row: 1, column: 8, x: 8, y: 1.25),
        .init(row: 1, column: 9, x: 9, y: 1.25), .init(row: 1, column: 10, x: 10, y: 1.25),
        .init(row: 1, column: 11, x: 11, y: 1.25), .init(row: 6, column: 4, x: 12, y: 1.25),
        .init(row: 6, column: 6, x: 13, y: 1.25, width: 2),
        .init(row: 6, column: 7, x: 15.5, y: 1.25), .init(row: 6, column: 8, x: 16.5, y: 1.25),
        .init(row: 1, column: 12, x: 18, y: 1.25), .init(row: 1, column: 13, x: 19, y: 1.25),
        .init(row: 1, column: 14, x: 20, y: 1.25), .init(row: 1, column: 15, x: 21, y: 1.25),

        // Q row.
        .init(row: 2, column: 0, x: 0, y: 2.25, width: 1.5),
        .init(row: 2, column: 1, x: 1.5, y: 2.25), .init(row: 2, column: 2, x: 2.5, y: 2.25),
        .init(row: 2, column: 3, x: 3.5, y: 2.25), .init(row: 2, column: 4, x: 4.5, y: 2.25),
        .init(row: 2, column: 5, x: 5.5, y: 2.25), .init(row: 2, column: 6, x: 6.5, y: 2.25),
        .init(row: 2, column: 7, x: 7.5, y: 2.25), .init(row: 2, column: 8, x: 8.5, y: 2.25),
        .init(row: 2, column: 9, x: 9.5, y: 2.25), .init(row: 2, column: 10, x: 10.5, y: 2.25),
        .init(row: 2, column: 11, x: 11.5, y: 2.25), .init(row: 6, column: 10, x: 12.5, y: 2.25),
        .init(row: 6, column: 11, x: 13.5, y: 2.25, width: 1.5),
        .init(row: 6, column: 12, x: 15.5, y: 2.25), .init(row: 6, column: 13, x: 16.5, y: 2.25),
        .init(row: 2, column: 12, x: 18, y: 2.25), .init(row: 2, column: 13, x: 19, y: 2.25),
        .init(row: 2, column: 14, x: 20, y: 2.25), .init(row: 2, column: 15, x: 21, y: 2.25, height: 2),

        // A row.
        .init(row: 3, column: 0, x: 0, y: 3.25, width: 1.75),
        .init(row: 3, column: 1, x: 1.75, y: 3.25), .init(row: 3, column: 2, x: 2.75, y: 3.25),
        .init(row: 3, column: 3, x: 3.75, y: 3.25), .init(row: 3, column: 4, x: 4.75, y: 3.25),
        .init(row: 3, column: 5, x: 5.75, y: 3.25), .init(row: 3, column: 6, x: 6.75, y: 3.25),
        .init(row: 3, column: 7, x: 7.75, y: 3.25), .init(row: 3, column: 8, x: 8.75, y: 3.25),
        .init(row: 3, column: 9, x: 9.75, y: 3.25), .init(row: 3, column: 10, x: 10.75, y: 3.25),
        .init(row: 3, column: 11, x: 11.75, y: 3.25),
        .init(row: 3, column: 12, x: 12.75, y: 3.25, width: 2.25),
        .init(row: 3, column: 13, x: 18, y: 3.25), .init(row: 3, column: 14, x: 19, y: 3.25),
        .init(row: 3, column: 15, x: 20, y: 3.25),

        // Z row and arrows/numpad.
        .init(row: 4, column: 0, x: 0, y: 4.25, width: 2.25),
        .init(row: 4, column: 2, x: 2.25, y: 4.25), .init(row: 4, column: 3, x: 3.25, y: 4.25),
        .init(row: 4, column: 4, x: 4.25, y: 4.25), .init(row: 4, column: 5, x: 5.25, y: 4.25),
        .init(row: 4, column: 6, x: 6.25, y: 4.25), .init(row: 4, column: 7, x: 7.25, y: 4.25),
        .init(row: 4, column: 8, x: 8.25, y: 4.25), .init(row: 4, column: 9, x: 9.25, y: 4.25),
        .init(row: 4, column: 10, x: 10.25, y: 4.25), .init(row: 4, column: 11, x: 11.25, y: 4.25),
        .init(row: 6, column: 14, x: 12.25, y: 4.25, width: 2.75),
        .init(row: 4, column: 12, x: 15.5, y: 4.25),
        .init(row: 4, column: 13, x: 18, y: 4.25), .init(row: 4, column: 14, x: 19, y: 4.25),
        .init(row: 4, column: 15, x: 20, y: 4.25), .init(row: 5, column: 15, x: 21, y: 4.25, height: 2),

        // Bottom row.
        .init(row: 5, column: 0, x: 0, y: 5.25, width: 1.25),
        .init(row: 5, column: 1, x: 1.25, y: 5.25, width: 1.25),
        .init(row: 5, column: 2, x: 2.5, y: 5.25, width: 1.25),
        .init(row: 5, column: 5, x: 3.75, y: 5.25, width: 6.25),
        .init(row: 5, column: 6, x: 10, y: 5.25, width: 1.25),
        .init(row: 5, column: 7, x: 11.25, y: 5.25, width: 1.25),
        .init(row: 5, column: 8, x: 12.5, y: 5.25, width: 1.25),
        .init(row: 5, column: 10, x: 14.5, y: 5.25),
        .init(row: 5, column: 11, x: 15.5, y: 5.25),
        .init(row: 5, column: 12, x: 16.5, y: 5.25),
        .init(row: 5, column: 13, x: 18, y: 5.25, width: 2),
        .init(row: 5, column: 14, x: 20, y: 5.25),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .darkGray).gradient)
            screenModule
            ForEach(Self.specs) { spec in
                if let key = keys.first(where: { $0.row == spec.row && $0.column == spec.column }) {
                    physicalKey(key, spec: spec)
                }
            }
        }
        .frame(width: position(22), height: position(6.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var screenModule: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.black.opacity(0.7))
            .overlay {
                VStack(spacing: 2) {
                    Image(systemName: "display")
                    Text("Zoom98 Screen").font(.system(size: 7, weight: .medium))
                }
                .foregroundStyle(.mint)
            }
            .frame(width: keySize(2.25).width, height: keySize(1).height)
            .offset(x: position(15.5), y: position(0))
    }

    private func physicalKey(_ key: KeyboardKey, spec: PhysicalKeySpec) -> some View {
        Button { edit(key) } label: {
            Text(KeycodeCatalog.displayName(for: key.keycode, macMode: macMode))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(key.keycode == 0 ? .gray : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(key.keycode == 0 ? Color.black.opacity(0.25) : Color(nsColor: .controlTextColor).opacity(0.72))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .help("\(KeycodeCatalog.name(for: key.keycode)) · 矩阵 \(key.row),\(key.column)")
        .frame(width: keySize(spec.width).width, height: keySize(spec.height).height)
        .offset(x: position(spec.x), y: position(spec.y))
    }

    private func position(_ value: CGFloat) -> CGFloat { value * (unit + gap) }
    private func keySize(_ value: CGFloat) -> CGSize {
        CGSize(width: value * unit + max(0, value - 1) * gap,
               height: value * unit + max(0, value - 1) * gap)
    }
}

private enum KeyAssignmentCategory: String, CaseIterable, Identifiable {
        case basic = "普通按键"
        case media = "Mac 媒体键"
        case macros = "文本宏"

        var id: Self { self }
        var icon: String {
            switch self {
            case .basic: "keyboard"
            case .media: "play.circle"
            case .macros: "text.badge.plus"
            }
        }
}

private final class KeyEditorModel: ObservableObject {
    @Published var category: KeyAssignmentCategory
    @Published var search = ""

    init(code: UInt16) {
        if (0x00A8...0x00BE).contains(code) {
            category = .media
        } else if (0x7700...0x770F).contains(code) {
            category = .macros
        } else {
            category = .basic
        }
    }
}

private struct KeyEditorSheet: View {
    @ObservedObject var controller: KeyboardController
    @StateObject private var model: KeyEditorModel
    let key: KeyboardKey

    init(controller: KeyboardController, key: KeyboardKey) {
        self.controller = controller
        self.key = key
        _model = StateObject(wrappedValue: KeyEditorModel(code: key.keycode))
    }

    private func filtered(_ entries: [(UInt16, String)]) -> [(UInt16, String)] {
        guard !model.search.isEmpty else { return entries }
        return entries.filter {
            $0.1.localizedCaseInsensitiveContains(model.search) ||
            KeycodeCatalog.displayName(for: $0.0, macMode: true).localizedCaseInsensitiveContains(model.search)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择功能")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                ForEach(KeyAssignmentCategory.allCases) { item in
                    Button {
                        model.category = item
                        model.search = ""
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(model.category == item ? Color.accentColor.opacity(0.14) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Label("写入键盘存储", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .padding(12)
            .frame(width: 180)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("修改按键")
                                .font(.title2.weight(.semibold))
                            Text("主键层 · 矩阵 R\(key.row) C\(key.column)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("当前选择")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(KeycodeCatalog.displayName(for: controller.selectedKeycode, macMode: true))
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(String(format: "0x%04X", controller.selectedKeycode))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if ShortcutKeycode.isModified(controller.selectedKeycode) {
                        Label("这版固件会保存该组合键码，但按下不会执行；请改为普通键、媒体键或文本宏",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    } else if KeycodeCatalog.isUnsupportedMacMedia(controller.selectedKeycode) {
                        Label("这是 Windows/Linux 消费控制键，macOS 不会执行；请改为下方可用的 Mac 媒体键",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    } else {
                        Label("保存在键盘 · USB 与蓝牙均可用", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12))

                Divider()

                Group {
                    switch model.category {
                    case .basic:
                        searchableKeyList(KeycodeCatalog.basicEntries, placeholder: "搜索字母、数字、方向键…")
                    case .media:
                        searchableKeyList(KeycodeCatalog.macMediaEntries, placeholder: "搜索音量、播放、亮度…")
                    case .macros:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("先在“文本宏”页面填写内容，再把对应的 M0–M15 分配到这里。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            keyList(KeycodeCatalog.macroEntries)
                        }
                    }
                }

                Divider()
                HStack {
                    Text("应用后立即写入当前键位")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { controller.finishEditing(save: false) }
                    Button("应用到按键") { controller.finishEditing(save: true) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 900, height: 680)
    }

    private func searchableKeyList(_ entries: [(UInt16, String)], placeholder: String) -> some View {
        VStack(spacing: 10) {
            TextField(placeholder, text: $model.search)
                .textFieldStyle(.roundedBorder)
            keyList(filtered(entries))
        }
    }

    private func keyList(_ entries: [(UInt16, String)]) -> some View {
        List(entries, id: \.0) { entry in
            assignmentRow(code: entry.0, title: KeycodeCatalog.displayName(for: entry.0, macMode: true), detail: entry.1)
        }
        .listStyle(.inset)
    }

    private func assignmentRow(code: UInt16, title: String, detail: String) -> some View {
        Button {
            controller.selectedKeycode = code
        } label: {
            HStack(spacing: 10) {
                Image(systemName: controller.selectedKeycode == code ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(controller.selectedKeycode == code ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "0x%04X", code))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

private struct MacroPage: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("16 个文本宏 · 总容量 \(controller.macroBufferSize) 字节")
                    .font(.headline)
                Spacer()
                Text("\(controller.macroUsedBytes) / \(controller.macroBufferSize) 字节")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(controller.macrosFitBuffer ? Color.secondary : Color.red)
                Button("保存全部宏") { controller.saveMacros() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.isConnected || !controller.macrosAreASCII || !controller.macrosFitBuffer)
            }
            Text("当前版本支持固件原生的 ASCII 文本宏。保存后可在键位页把 M0–M15 对应的宏键码分配到按键。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(
                value: Double(min(controller.macroUsedBytes, max(1, controller.macroBufferSize))),
                total: Double(max(1, controller.macroBufferSize))
            )
            if !controller.macrosAreASCII {
                Label("固件只接受 ASCII；中文、全角符号和 Emoji 无法保存", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !controller.macrosFitBuffer {
                Label("文本宏已超过键盘容量，请缩短内容", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Label("宏以明文保存在键盘和导出的配置中，请勿存放密码", systemImage: "lock.open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(controller.macros.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline) {
                            Text("M\(index)")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(width: 32)
                            TextField("输入要自动键入的文字", text: $controller.macros[index])
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(.top, 10)
    }
}

private struct BottomLightInfoCard: View {
    private let shortcuts = [
        ("开关", "Fn + Shift + \\"),
        ("切换效果", "Fn + Shift + ]"),
        ("增加 / 减少色相", "Fn + Shift + P / ;"),
        ("增加 / 减少饱和度", "Fn + Shift + [ / '"),
        ("提高 / 降低亮度", "Fn + Shift + ↑ / ↓"),
        ("加快 / 减慢速度", "Fn + Shift + → / ←"),
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("这版固件未开放侧灯的软件寄存器", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("侧边灯条（官方称 Bottom Light）可以独立控制，但目前只能由键盘固件快捷键调整。工具不会向无效的 RGB Light 接口写入。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                ForEach(shortcuts, id: \.0) { item in
                    HStack {
                        Text(item.0)
                        Spacer()
                        Text(item.1)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Label("已保留协议研究入口，找到自定义命令后可直接接入", systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("侧边灯条", systemImage: "lightstrip.2")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LightingCard: View {
    let channel: LightingChannel
    @Binding var state: LightingState
    @AppStorage("showExperimentalLightingEffects") private var showExperimentalEffects = false
    let enabled: Bool
    let apply: (LightingChannel, LightingState) -> Void
    let save: () -> Void

    private var color: Binding<Color> {
        Binding(
            get: {
                Color(
                    hue: Double(state.hue) / 255,
                    saturation: Double(state.saturation) / 255,
                    brightness: 1
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                state.hue = UInt8(clamping: Int((hue * 255).rounded()))
                state.saturation = UInt8(clamping: Int((saturation * 255).rounded()))
            }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    ColorPicker("颜色", selection: color, supportsOpacity: false)
                    Spacer()
                    Button(state.brightness == 0 ? "开启" : "关闭") {
                        state.brightness = state.brightness == 0 ? 153 : 0
                        apply(channel, state)
                    }
                }
                ValueSlider(title: "亮度", value: binding(\.brightness))
                ValueSlider(title: "速度", value: binding(\.speed))
                VStack(alignment: .leading, spacing: 6) {
                    Text("灯效")
                    Picker("灯效", selection: $state.effect) {
                        ForEach(effectValues, id: \.self) { value in
                            Text("\(effectName(value)) · \(value)").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("显示未验证的固件效果 18–31", isOn: $showExperimentalEffects)
                        .font(.caption)
                }
                LightingPreview(state: state, effectName: effectName(state.effect))
                HStack {
                    Spacer()
                    Button("应用") { apply(channel, state) }
                    Button("应用并保存") {
                        apply(channel, state)
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
        } label: {
            Label(channel.rawValue, systemImage: channel == .keys ? "keyboard" : "lightstrip.2")
                .font(.headline)
        }
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
    }

    private func effectName(_ value: UInt8) -> String {
        let names: [UInt8: String] = [
            0: "关闭", 1: "纯色常亮", 2: "按键与修饰键", 3: "上下渐变",
            4: "左右渐变", 5: "呼吸", 6: "色带饱和度", 7: "色带亮度",
            8: "彩虹风车", 9: "彩虹水平移动", 10: "彩虹斜向移动",
            11: "跑马灯", 12: "双色循环", 13: "彩虹循环",
            14: "信标", 15: "像素雨", 16: "按键涟漪", 17: "按键飞溅",
        ]
        return names[value] ?? "固件效果 \(value)"
    }

    private var effectValues: [UInt8] {
        var values = Array(0...17).map(UInt8.init)
        if showExperimentalEffects {
            values += Array(18...31).map(UInt8.init)
        } else if state.effect > 17 {
            values.append(state.effect)
        }
        return values
    }

    private func binding(_ keyPath: WritableKeyPath<LightingState, UInt8>) -> Binding<Double> {
        Binding(
            get: { Double(state[keyPath: keyPath]) },
            set: { state[keyPath: keyPath] = UInt8(clamping: Int($0.rounded())) }
        )
    }
}

private struct LightingPreview: View {
    let state: LightingState
    let effectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("灯光预览", systemImage: "eye")
                    .font(.headline)
                Spacer()
                Text("\(effectName) · 效果示意")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                Canvas { context, size in
                    drawKeyboard(in: &context, size: size, date: timeline.date)
                }
            }
            .frame(height: 205)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    private func drawKeyboard(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let logicalWidth: CGFloat = 22
        let logicalHeight: CGFloat = 6.5
        let padding: CGFloat = 13
        let unit = min((size.width - padding * 2) / logicalWidth,
                       (size.height - padding * 2) / logicalHeight)
        let contentSize = CGSize(width: logicalWidth * unit, height: logicalHeight * unit)
        let origin = CGPoint(x: (size.width - contentSize.width) / 2,
                             y: (size.height - contentSize.height) / 2)
        let keyGap = max(1.5, unit * 0.075)
        let time = date.timeIntervalSinceReferenceDate
        let speed = 0.35 + Double(state.speed) / 255.0 * 2.8
        let phase = time * speed

        for spec in Zoom98PhysicalKeymapView.specs {
            let rect = CGRect(
                x: origin.x + spec.x * unit + keyGap / 2,
                y: origin.y + spec.y * unit + keyGap / 2,
                width: spec.width * unit - keyGap,
                height: spec.height * unit - keyGap
            )
            let path = Path(roundedRect: rect, cornerRadius: max(2.5, unit * 0.10))
            context.fill(path, with: .color(Color.white.opacity(0.08)))
            let light = previewColor(
                x: Double((spec.x + spec.width / 2) / logicalWidth),
                y: Double((spec.y + spec.height / 2) / logicalHeight),
                row: Int(spec.row),
                column: Int(spec.column),
                phase: phase
            )
            context.fill(path, with: .color(light))
            context.stroke(path, with: .color(Color.white.opacity(0.14)), lineWidth: 0.7)
        }

        let screenRect = CGRect(x: origin.x + 15.5 * unit + keyGap / 2,
                                y: origin.y + keyGap / 2,
                                width: 2.25 * unit - keyGap,
                                height: unit - keyGap)
        let screenPath = Path(roundedRect: screenRect, cornerRadius: max(2.5, unit * 0.10))
        context.fill(screenPath, with: .color(Color.black.opacity(0.92)))
        context.stroke(screenPath, with: .color(Color.mint.opacity(0.45)), lineWidth: 0.8)
        let screenLabel = context.resolve(
            Text("SCREEN")
                .font(.system(size: max(5, unit * 0.20), weight: .semibold))
                .foregroundStyle(Color.mint.opacity(0.8))
        )
        context.draw(screenLabel, at: CGPoint(x: screenRect.midX, y: screenRect.midY))
    }

    private func previewColor(x: Double, y: Double, row: Int, column: Int,
                              phase: Double) -> Color {
        guard state.brightness > 0, state.effect != 0 else { return .clear }
        let brightness = 0.12 + Double(state.brightness) / 255.0 * 0.88
        let baseHue = Double(state.hue) / 255.0
        let saturation = Double(state.saturation) / 255.0
        var hue = baseHue
        var adjustedSaturation = max(0.08, saturation)
        var opacity = brightness

        switch state.effect {
        case 2:
            opacity *= (y > 0.78 || column.isMultiple(of: 5)) ? 1 : 0.22
        case 3:
            opacity *= 0.28 + 0.72 * wave(phase + y * .pi * 2)
        case 4:
            opacity *= 0.28 + 0.72 * wave(phase + x * .pi * 2)
        case 5:
            opacity *= 0.18 + 0.82 * wave(phase)
        case 6: // 色带饱和度
            adjustedSaturation = 0.08 + 0.92 * wave(phase + x * .pi * 2)
        case 7: // 色带亮度
            opacity *= 0.16 + 0.84 * wave(phase + x * .pi * 2)
        case 8: // 彩虹风车：颜色围绕中心旋转
            let angle = atan2(y - 0.5, x - 0.5) / (.pi * 2)
            hue = wrapped(baseHue + angle + phase * 0.07)
        case 9: // 彩虹水平移动
            hue = wrapped(baseHue + x * 0.95 - phase * 0.08)
        case 10: // 彩虹斜向移动
            hue = wrapped(baseHue + (x + y) * 0.62 - phase * 0.08)
        case 11: // 跑马灯：一条明亮光带横向扫过
            let head = wrapped(phase * 0.13)
            let distance = circularDistance(x, head)
            opacity *= 0.08 + 0.92 * max(0, 1 - distance / 0.16)
        case 12: // 双色循环：相邻键使用互补色并交替
            let alternating = (row + column).isMultiple(of: 2)
            let swap = wave(phase * 0.8) > 0.5
            hue = wrapped(baseHue + ((alternating != swap) ? 0 : 0.5))
            opacity *= 0.52 + 0.48 * wave(phase + (alternating ? 0 : .pi))
        case 13: // 彩虹循环：整把键盘同时循环换色
            hue = wrapped(baseHue + phase * 0.10)
        case 14: // 信标：窄光束围绕中心旋转
            let angle = wrapped(atan2(y - 0.5, x - 0.5) / (.pi * 2))
            let beam = wrapped(phase * 0.10)
            let distance = circularDistance(angle, beam)
            opacity *= 0.08 + 0.92 * max(0, 1 - distance / 0.12)
            hue = wrapped(baseHue + angle * 0.3)
        case 15: // 像素雨：每列以不同相位向下坠落
            let seed = wrapped(sin(Double(column * 73 + 19)) * 43758.5453)
            let drop = wrapped(phase * (0.08 + seed * 0.06) + seed)
            let distance = circularDistance(y, drop)
            opacity *= 0.06 + 0.94 * max(0, 1 - distance / 0.22)
            hue = wrapped(baseHue + seed * 0.32)
        case 16: // 按键涟漪：由中心向外扩散的环
            let distance = hypot(x - 0.5, y - 0.5)
            let ring = circularDistance(wrapped(distance * 1.8), wrapped(phase * 0.16))
            opacity *= 0.10 + 0.90 * max(0, 1 - ring / 0.11)
        case 17: // 按键飞溅：分散的亮点快速闪烁
            let seed = wrapped(sin(Double(row * 91 + column * 47 + 7)) * 24634.6345)
            opacity *= 0.08 + 0.92 * pow(wave(phase * 2.4 + seed * .pi * 2), 9)
            hue = wrapped(baseHue + seed * 0.18)
        default:
            break
        }
        return Color(hue: hue, saturation: adjustedSaturation, brightness: 1, opacity: opacity)
    }

    private func wave(_ value: Double) -> Double { (sin(value) + 1) / 2 }
    private func circularDistance(_ first: Double, _ second: Double) -> Double {
        let direct = abs(first - second)
        return min(direct, 1 - direct)
    }
    private func wrapped(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 1)
        return result < 0 ? result + 1 : result
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...255, step: 1)
        }
    }
}
