import AppKit
import Combine
import Sparkle

/// Owns the signed Sparkle updater shared by the menu and preferences window.
@MainActor
final class AppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var unavailableReason: String?

    let versionDescription: String
    private var controller: SPUStandardUpdaterController?
    private let releasesURL = URL(string: "https://github.com/csyasin/lunera/releases")!

    override init() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        versionDescription = "版本 \(version)（构建 \(build)）"
        super.init()

        // Xcode expands this build setting as YES/NO; accept a plist Bool too.
        let flag = bundle.object(forInfoDictionaryKey: "LuneraUpdatesEnabled")
        let enabled = (flag as? Bool) == true || (flag as? String)?.uppercased() == "YES"
        guard enabled else {
            unavailableReason = "开发构建不检查更新，请使用 GitHub 发布版"
            return
        }
        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let decodedKey = Data(base64Encoded: publicKey), decodedKey.count == 32,
              let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              feed == "https://github.com/csyasin/lunera/releases/latest/download/appcast.xml" else {
            unavailableReason = "更新服务尚未完成安全配置"
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .receive(on: RunLoop.main).assign(to: &$automaticallyChecksForUpdates)
            controller.updater.publisher(for: \.lastUpdateCheckDate)
                .receive(on: RunLoop.main).assign(to: &$lastUpdateCheckDate)
        } catch {
            unavailableReason = "更新服务暂不可用：\(error.localizedDescription)"
            NSLog("Lunera updater: %@", error.localizedDescription)
        }
    }

    var statusMessage: String {
        if let reason = unavailableReason { return reason }
        if let version = availableVersion { return "发现新版本 \(version)" }
        if let date = lastUpdateCheckDate {
            return "上次检查：\(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "尚未检查更新"
    }

    var canOpenReleasesPage: Bool { true }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard unavailableReason == nil else { return }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }

    // There is no separate menu-bar update badge yet; let Sparkle present its
    // standard scheduled-update reminder instead of suppressing it.
    var supportsGentleScheduledUpdateReminders: Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
