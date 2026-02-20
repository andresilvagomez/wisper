import Foundation

final class DictationEditingService {
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let historyLimit: Int

    init(historyLimit: Int = 30) {
        self.historyLimit = historyLimit
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func snapshot(currentText: String) {
        undoStack.append(currentText)
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
    }

    func applyCommand(_ command: TextPostProcessor.EditingCommand, currentText: String) -> String? {
        switch command {
        case .deleteLastSentence:
            let updated = TextPostProcessor.removingLastSentence(from: currentText)
            guard updated != currentText else { return nil }
            snapshot(currentText: currentText)
            return updated
        case .undo:
            guard let previous = undoStack.popLast() else { return nil }
            redoStack.append(currentText)
            return previous
        case .redo:
            guard let next = redoStack.popLast() else { return nil }
            undoStack.append(currentText)
            return next
        }
    }
}
