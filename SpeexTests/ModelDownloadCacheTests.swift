import Foundation
import Testing
@testable import Speex

@Suite("Model Download Cache")
struct ModelDownloadCacheTests {

    @Test("Model folder is invalid when empty")
    func emptyFolderInvalid() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        #expect(!TranscriptionEngine.isModelFolderValid(temp))
    }

    @Test("Model folder is valid when it contains files")
    func nonEmptyFolderValid() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let marker = temp.appendingPathComponent("weights.bin")
        try Data([1, 2, 3]).write(to: marker)

        #expect(TranscriptionEngine.isModelFolderValid(temp))
    }
}

