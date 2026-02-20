import Foundation

struct AudioInputSelectionResult: Equatable {
    let availableDevices: [AudioInputDevice]
    let selectedDeviceUID: String
}

@MainActor
final class AudioInputSelectionCoordinator {
    func resolveSelection(
        devices: [AudioInputDevice],
        currentSelection: String,
        defaultDeviceUID: String?
    ) -> AudioInputSelectionResult {
        guard !devices.isEmpty else {
            return AudioInputSelectionResult(availableDevices: [], selectedDeviceUID: "")
        }

        if devices.count == 1 {
            return AudioInputSelectionResult(
                availableDevices: devices,
                selectedDeviceUID: devices[0].id
            )
        }

        if devices.contains(where: { $0.id == currentSelection }) {
            return AudioInputSelectionResult(
                availableDevices: devices,
                selectedDeviceUID: currentSelection
            )
        }

        if let defaultDeviceUID,
           devices.contains(where: { $0.id == defaultDeviceUID }) {
            return AudioInputSelectionResult(
                availableDevices: devices,
                selectedDeviceUID: defaultDeviceUID
            )
        }

        return AudioInputSelectionResult(
            availableDevices: devices,
            selectedDeviceUID: devices[0].id
        )
    }

    func captureInputDeviceUID(
        selectedDeviceUID: String,
        availableDevices: [AudioInputDevice]
    ) -> String? {
        guard !selectedDeviceUID.isEmpty else { return nil }
        guard availableDevices.contains(where: { $0.id == selectedDeviceUID }) else { return nil }
        return selectedDeviceUID
    }

    func selectedInputDeviceName(
        selectedDeviceUID: String,
        availableDevices: [AudioInputDevice],
        fallbackName: String
    ) -> String {
        availableDevices.first(where: { $0.id == selectedDeviceUID })?.name
            ?? availableDevices.first?.name
            ?? fallbackName
    }
}
