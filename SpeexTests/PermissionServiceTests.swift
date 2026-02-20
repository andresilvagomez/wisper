@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Speex

@Suite("Permission Service")
struct PermissionServiceTests {
    private final class MockAccessibilityProvider: AccessibilityPermissionProvider {
        var hasAccessibility: Bool
        var setupCalls = 0
        var recheckCalls = 0

        init(hasAccessibility: Bool) {
            self.hasAccessibility = hasAccessibility
        }

        func setup() { setupCalls += 1 }
        func recheckAccessibility() { recheckCalls += 1 }
    }

    private final class SharedPermissionState: @unchecked Sendable {
        private let lock = NSLock()
        private var _status: AVAuthorizationStatus
        private var _requestCalls = 0

        init(status: AVAuthorizationStatus) {
            _status = status
        }

        func status() -> AVAuthorizationStatus {
            lock.lock()
            defer { lock.unlock() }
            return _status
        }

        func setStatus(_ status: AVAuthorizationStatus) {
            lock.lock()
            _status = status
            lock.unlock()
        }

        func incrementRequestCalls() {
            lock.lock()
            _requestCalls += 1
            lock.unlock()
        }

        func requestCalls() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return _requestCalls
        }
    }

    @Test("Refresh with prompt triggers setup and returns expected state")
    func refreshWithPrompt() {
        let micStatus = AVAuthorizationStatus.denied
        let service = PermissionService(
            microphoneStatusProvider: { micStatus },
            microphoneRequester: { true }
        )
        let provider = MockAccessibilityProvider(hasAccessibility: false)

        let state = service.refreshState(
            accessibilityProvider: provider,
            requestAccessibilityPrompt: true
        )

        #expect(provider.setupCalls == 1)
        #expect(provider.recheckCalls == 0)
        #expect(state.needsAccessibility == true)
        #expect(state.needsMicrophone == true)
        #expect(state.microphoneStatus == .denied)
    }

    @Test("Refresh without prompt triggers recheck")
    func refreshWithoutPrompt() {
        let service = PermissionService(
            microphoneStatusProvider: { .authorized },
            microphoneRequester: { true }
        )
        let provider = MockAccessibilityProvider(hasAccessibility: true)

        let state = service.refreshState(
            accessibilityProvider: provider,
            requestAccessibilityPrompt: false
        )

        #expect(provider.setupCalls == 0)
        #expect(provider.recheckCalls == 1)
        #expect(state.needsAccessibility == false)
        #expect(state.needsMicrophone == false)
        #expect(state.microphoneStatus == .authorized)
    }

    @Test("Request microphone asks only when status is notDetermined")
    func requestMicrophoneWhenNotDetermined() async {
        let shared = SharedPermissionState(status: .notDetermined)
        let service = PermissionService(
            microphoneStatusProvider: { shared.status() },
            microphoneRequester: {
                shared.incrementRequestCalls()
                shared.setStatus(.authorized)
                return true
            }
        )

        let state = await service.requestMicrophonePermissionIfNeeded()
        #expect(shared.requestCalls() == 1)
        #expect(state.needsMicrophone == false)
        #expect(state.microphoneStatus == .authorized)
    }
}
