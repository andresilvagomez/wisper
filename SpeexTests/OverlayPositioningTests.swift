import AppKit
import Foundation
import Testing
@testable import Speex

@Suite("Overlay Positioning")
struct OverlayPositioningTests {

    @Test("Default origin is inside visible frame")
    func defaultOriginIsVisible() {
        let frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: 360, height: 48)

        let origin = OverlayPositioning.defaultOrigin(panelSize: size, visibleFrame: frame)

        #expect(origin.x >= frame.minX)
        #expect(origin.y >= frame.minY)
        #expect(origin.x + size.width <= frame.maxX)
        #expect(origin.y + size.height <= frame.maxY)
    }

    @Test("Clamping keeps overlay inside screen bounds")
    func clampedOriginStaysOnScreen() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = CGSize(width: 360, height: 48)
        let desired = NSPoint(x: 9999, y: -9999)

        let origin = OverlayPositioning.clampedOrigin(desired: desired, panelSize: size, visibleFrame: frame)

        #expect(origin.x + size.width <= frame.maxX)
        #expect(origin.x >= frame.minX)
        #expect(origin.y + size.height <= frame.maxY)
        #expect(origin.y >= frame.minY)
    }

    @Test("Position storage persists and restores values")
    func storageRoundTrip() {
        let suite = "overlay-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Could not create test defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)

        let storage = OverlayPositionStorage(defaults: defaults)
        let point = NSPoint(x: 140, y: 240)
        storage.save(point)

        let loaded = storage.load()
        #expect(loaded?.x == point.x)
        #expect(loaded?.y == point.y)

        storage.clear()
        #expect(storage.load() == nil)
    }
}
