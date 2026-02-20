import Foundation
import Testing
@testable import Speex

@Suite("Audio Input Selection Coordinator")
@MainActor
struct AudioInputSelectionCoordinatorTests {
    private let micA = AudioInputDevice(id: "a", name: "Mic A")
    private let micB = AudioInputDevice(id: "b", name: "Mic B")

    @Test("Empty devices clears selection")
    func emptyDevices() {
        let coordinator = AudioInputSelectionCoordinator()
        let result = coordinator.resolveSelection(
            devices: [],
            currentSelection: "a",
            defaultDeviceUID: "b"
        )

        #expect(result.availableDevices.isEmpty)
        #expect(result.selectedDeviceUID.isEmpty)
    }

    @Test("Single device is auto-selected")
    func singleDevice() {
        let coordinator = AudioInputSelectionCoordinator()
        let result = coordinator.resolveSelection(
            devices: [micA],
            currentSelection: "",
            defaultDeviceUID: nil
        )

        #expect(result.selectedDeviceUID == "a")
    }

    @Test("Keeps current selection when still available")
    func keepCurrentSelection() {
        let coordinator = AudioInputSelectionCoordinator()
        let result = coordinator.resolveSelection(
            devices: [micA, micB],
            currentSelection: "b",
            defaultDeviceUID: "a"
        )

        #expect(result.selectedDeviceUID == "b")
    }

    @Test("Falls back to default device when current selection is missing")
    func fallbackToDefaultDevice() {
        let coordinator = AudioInputSelectionCoordinator()
        let result = coordinator.resolveSelection(
            devices: [micA, micB],
            currentSelection: "x",
            defaultDeviceUID: "b"
        )

        #expect(result.selectedDeviceUID == "b")
    }

    @Test("Capture UID is nil when selected device is invalid")
    func captureUIDResolution() {
        let coordinator = AudioInputSelectionCoordinator()

        let valid = coordinator.captureInputDeviceUID(
            selectedDeviceUID: "a",
            availableDevices: [micA]
        )
        let invalid = coordinator.captureInputDeviceUID(
            selectedDeviceUID: "x",
            availableDevices: [micA]
        )

        #expect(valid == "a")
        #expect(invalid == nil)
    }
}
