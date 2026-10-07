import Foundation

final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.withLock { storage }
    }

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}

final class UnsafeCapture: @unchecked Sendable {
    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }
}

func stripLogTimestamp(_ line: String) -> String {
    guard let space = line.firstIndex(of: " ") else { return line }
    return String(line[line.index(after: space)...])
}

func styledTagKey(_ key: String) -> String {
    "\u{1B}[36m\(key)\u{1B}[0m: "
}

func rainbowBracket(_ bracket: Character, depth: Int) -> String {
    "\u{1B}[\([33, 35, 34][depth % 3])m\(bracket)\u{1B}[0m"
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func tagGap(after message: String, width: Int = 40) -> String {
    String(repeating: " ", count: max(1, width - message.count + 1))
}

func expectedLine(
    level: String,
    label: String = "gear",
    source: String = "MachinistTests",
    metadata: String = "",
    message: String
) -> String {
    let context = [label, source].filter { !$0.isEmpty }.joined(separator: ":")
    let columns = [
        pad("[\(context)]", 40),
        pad("[\(level.uppercased())]", 10),
    ].filter { !$0.isEmpty }
    let tags = metadata.isEmpty ? "" : "\(tagGap(after: message))(\(metadata))"
    return columns.joined(separator: " ") + " \(message)\(tags)\n"
}

struct PressureError: Error, CustomStringConvertible {
    let description = "pressure exceeded 9000 PSI"
}
