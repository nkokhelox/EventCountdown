import Foundation
import Observation
import ServiceManagement

@Observable
final class LaunchAtLoginService {
    private var isApplying = false

    var isEnabled: Bool {
        didSet {
            guard !isApplying else { return }
            UserDefaults.standard.set(isEnabled, forKey: AppConstants.launchAtLoginKey)
            applyPreference()
        }
    }

    private(set) var statusMessage: String?

    init() {
        isApplying = true
        isEnabled = UserDefaults.standard.bool(forKey: AppConstants.launchAtLoginKey)
        isApplying = false
        syncStatus()
        if isEnabled {
            applyPreference()
        }
    }

    func syncStatus() {
        isApplying = true
        defer { isApplying = false }
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            statusMessage = nil
            isEnabled = true
        case .requiresApproval:
            statusMessage = "Allow EventCountdown in System Settings → General → Login Items."
        case .notRegistered:
            if UserDefaults.standard.bool(forKey: AppConstants.launchAtLoginKey) {
                statusMessage = "Launch at login is not registered yet."
            } else {
                statusMessage = nil
            }
        case .notFound:
            statusMessage = "Login item not found. Re-enable the toggle."
        @unknown default:
            statusMessage = nil
        }
    }

    private func applyPreference() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            syncStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
