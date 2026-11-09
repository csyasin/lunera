import AppKit
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var updater: AppUpdater
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @StateObject private var customColorPicker = CustomColorPicker()
    @AppStorage(ThemeColor.preferenceKey) private var accentHex = ThemeColor.systemValue
    @AppStorage("appearance.accentSource") private var accentSource = ""
    @AppStorage("appearance.customAccentHex") private var customAccentHex = ""

    private var accent: Color { ThemeColor.color(accentHex) }
    private var colorSource: String {
        if ["system", "preset", "custom"].contains(accentSource) { return accentSource }
        if accentHex == ThemeColor.systemValue { return "system" }
        return ThemeColor.presets.contains { $0.hex == accentHex } ? "preset" : "custom"
    }
    private var updateStatus: String {
        if let reason = updater.unavailableReason { return reason }
        if let version = updater.availableVersion { return "发现新版本 \(version)" }
        if !updater.statusMessage.isEmpty { return updater.statusMessage }
        if let date = updater.lastUpdateCheckDate {
            return "上次检查：\(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "尚未检查更新"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            launchAtLoginSection
            themeSection
            updateSection
        }
        .padding(30)
        .frame(width: 680)
        .background(.background)
        .onAppear { launchAtLogin.refresh() }
        .onDisappear { customColorPicker.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .alert("无法设置开机自启", isPresented: Binding(
            get: { launchAtLogin.errorMessage != nil }, set: { if !$0 { launchAtLogin.errorMessage = nil } }
        )) { Button("好", role: .cancel) { launchAtLogin.errorMessage = nil } }
        message: { Text(launchAtLogin.errorMessage ?? "") }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("开机自启")
            HStack(spacing: 14) {
                rowIcon("power")
                Text(launchAtLogin.description)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if launchAtLogin.requiresApproval {
                    Button("打开系统设置") { launchAtLogin.openSystemSettings() }
                        .controlSize(.small)
                }
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLogin.isOn },
                    set: { enabled in
                        do { try launchAtLogin.setEnabled(enabled) }
                        catch { launchAtLogin.errorMessage = error.localizedDescription }
                    }
                ))
                .labelsHidden().toggleStyle(.switch).tint(accent)
                .accessibilityLabel("开机自启")
            }
            .padding(18)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("主题色")
            HStack(spacing: 12) {
                ForEach(ThemeColor.presets, id: \.hex) { preset in
                    Button { applyThemeColor(preset.hex, source: "preset") } label: {
                        themeSwatch(preset.hex, selected: colorSource == "preset" && accentHex == preset.hex)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name).accessibilityLabel(preset.name)
                    .accessibilityAddTraits(colorSource == "preset" && accentHex == preset.hex ? .isSelected : [])
                }
                Divider().frame(height: 24)
                Button { applyThemeColor(ThemeColor.systemValue, source: "system") } label: {
                    HStack(spacing: 6) {
                        themeSwatch(ThemeColor.systemValue, selected: colorSource == "system")
                        Text("跟随系统").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("使用系统主题色")
                .accessibilityLabel("跟随系统")
                .accessibilityAddTraits(colorSource == "system" ? .isSelected : [])
                Divider().frame(height: 24)
                HStack(spacing: 6) {
                    Button {
                        if customAccentHex.isEmpty { editCustomColor() }
                        else { applyThemeColor(customAccentHex, source: "custom") }
                    } label: {
                        HStack(spacing: 6) {
                            if customAccentHex.isEmpty {
                                Circle().fill(.quaternary)
                                    .frame(width: 29, height: 29)
                                    .overlay {
                                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(5)
                            } else {
                                themeSwatch(customAccentHex, selected: colorSource == "custom")
                            }
                            Text("自定义").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(customAccentHex.isEmpty ? "设置自定义主题色" : "使用上次的自定义主题色")
                    .accessibilityLabel("自定义")
                    .accessibilityAddTraits(colorSource == "custom" ? .isSelected : [])
                    Button { editCustomColor() } label: {
                        Image(systemName: "pencil").font(.system(size: 13))
                            .foregroundStyle(.secondary).frame(width: 24, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑自定义主题色")
                    .accessibilityLabel("编辑自定义主题色")
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("应用更新")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    rowIcon("arrow.triangle.2.circlepath")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updater.versionDescription).font(.system(size: 13, weight: .medium))
                        Text(updateStatus)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if updater.canOpenReleasesPage {
                        Button("发布页面") { updater.openReleasesPage() }
                    }
                    Button("检查更新…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                Divider().padding(.leading, 46)
                HStack(spacing: 14) {
                    rowIcon("clock")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动检查更新").font(.system(size: 13, weight: .medium))
                        Text("每天在后台检查，安装更新前会征求你的同意")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("自动检查更新", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    ))
                        .labelsHidden().toggleStyle(.switch).tint(accent)
                        .disabled(updater.unavailableReason != nil)
                        .accessibilityLabel("自动检查更新")
                }
            }
            .padding(18)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular))
            .foregroundStyle(.secondary).frame(width: 30)
    }

    private func themeSwatch(_ hex: String, selected: Bool) -> some View {
        Circle().fill(ThemeColor.color(hex))
            .frame(width: 29, height: 29)
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ThemeColor.keyInk(hex))
                }
            }
            .padding(5)
            .overlay(Circle().strokeBorder(selected ? ThemeColor.color(hex).opacity(0.8) : .clear, lineWidth: 1.5))
            .contentShape(Circle())
    }

    private func applyThemeColor(_ hex: String, source: String) {
        customColorPicker.close()
        accentSource = source
        accentHex = hex
    }

    private func editCustomColor() {
        if customAccentHex.isEmpty {
            customAccentHex = ThemeColor.hex(accent) ?? "9EE8C9"
        }
        accentSource = "custom"
        accentHex = customAccentHex
        customColorPicker.open(selection: Binding(
            get: { ThemeColor.color(customAccentHex) },
            set: { color in
                guard let hex = ThemeColor.hex(color) else { return }
                customAccentHex = hex
                accentSource = "custom"
                accentHex = hex
            }
        ))
    }
}

@MainActor
private final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published var errorMessage: String?
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }
    var description: String {
        switch status {
        case .enabled: "登录 Mac 后自动在菜单栏运行"
        case .requiresApproval: "需要在系统设置的登录项中允许 Lunera"
        case .notRegistered, .notFound: "登录 Mac 后自动启动 Lunera"
        @unknown default: "请在系统设置中检查登录项状态"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        refresh()
        defer { refresh() }
        guard enabled != isOn else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw LaunchAtLoginError.appBundleRequired
        }
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

private enum LaunchAtLoginError: LocalizedError {
    case appBundleRequired
    var errorDescription: String? { "请打开构建后的 Lunera.app，再设置开机自启。" }
}

@MainActor
private final class CustomColorPicker: NSObject, ObservableObject {
    private var selection: SwiftUI.Binding<Color>?
    func open(selection: SwiftUI.Binding<Color>) {
        self.selection = selection
        let panel = NSColorPanel.shared
        let color = NSColor(selection.wrappedValue)
        panel.color = color.usingColorSpace(.sRGB) ?? color
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func colorChanged(_ sender: NSColorPanel) {
        selection?.wrappedValue = Color(nsColor: sender.color)
    }
    func close() {
        guard selection != nil else { return }
        selection = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.close()
    }
}
