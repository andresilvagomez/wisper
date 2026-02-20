@preconcurrency import AVFoundation
import Foundation

protocol AccessibilityPermissionProvider: AnyObject {
    var hasAccessibility: Bool { get }
    func setup()
    func recheckAccessibility()
}

extension TextInjector: AccessibilityPermissionProvider {}

struct PermissionState: Equatable {
    let needsAccessibility: Bool
    let needsMicrophone: Bool
    let microphoneStatus: AVAuthorizationStatus
}

enum SystemPermission {
    case accessibility
    case microphone
}

final class PermissionService: @unchecked Sendable {
    private let microphoneStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let microphoneRequester: @Sendable () async -> Bool

    init(
        microphoneStatusProvider: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        microphoneRequester: @escaping @Sendable () async -> Bool = {
            await AudioEngine.requestPermission()
        }
    ) {
        self.microphoneStatusProvider = microphoneStatusProvider
        self.microphoneRequester = microphoneRequester
    }

    func refreshState(
        accessibilityProvider: AccessibilityPermissionProvider?,
        requestAccessibilityPrompt: Bool
    ) -> PermissionState {
        if requestAccessibilityPrompt {
            accessibilityProvider?.setup()
        } else {
            accessibilityProvider?.recheckAccessibility()
        }

        let micStatus = microphoneStatusProvider()
        return PermissionState(
            needsAccessibility: !(accessibilityProvider?.hasAccessibility ?? false),
            needsMicrophone: micStatus != .authorized,
            microphoneStatus: micStatus
        )
    }

    func requestMicrophonePermissionIfNeeded() async -> PermissionState {
        let currentStatus = microphoneStatusProvider()
        if currentStatus == .notDetermined {
            let granted = await microphoneRequester()
            let resolvedStatus = granted ? AVAuthorizationStatus.authorized : microphoneStatusProvider()
            return PermissionState(
                needsAccessibility: false,
                needsMicrophone: !granted,
                microphoneStatus: resolvedStatus
            )
        }

        return PermissionState(
            needsAccessibility: false,
            needsMicrophone: currentStatus != .authorized,
            microphoneStatus: currentStatus
        )
    }

    func settingsURL(for permission: SystemPermission) -> URL? {
        let urlString: String
        switch permission {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }

        return URL(string: urlString)
    }
}
