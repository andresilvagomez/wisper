import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: String // CoreAudio device UID
    let name: String
}
