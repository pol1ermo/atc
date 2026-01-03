import Foundation

struct Transcription: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let isFinal: Bool

    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), isFinal: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
