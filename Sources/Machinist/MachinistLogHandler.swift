#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unsupported runtime")
#endif

import Foundation
import Logging

/// A `LogHandler` that formats each message and forwards it to an `Output`.
///
/// Each message becomes one line — a timestamp, a `[label:source]` bracket, a
/// `[LEVEL]` token, the message, and any metadata tags in parentheses:
///
///     2026-09-30T18:11:04-0700 [com.example.machinist:MachinistTests]   [INFO]     listening on port 9000                   (app: machinistd, request-id: A1B2C3)
///
/// The level, label:source, and message columns are padded per
/// ``justification`` so the message and its tags each start at the same
/// column on nearly every line; wide fields overflow untouched — padding
/// never truncates. Tag keys are listed in the
/// order they were added rather than alphabetically: keys set on the logger
/// first, then provider keys, then per-statement keys, then error details;
/// reassigning an existing key keeps its original position. Keys delivered as
/// a whole metadata dictionary — by a provider or at a log statement — are
/// ordered alphabetically among themselves, since a dictionary does not
/// preserve the order its entries were written in.
///
/// Metadata is merged from the same sources in the same order as swift-log's
/// `StreamLogHandler`:
/// 1. Metadata set on the log handler itself is used as the base metadata.
/// 2. The handler's ``metadataProvider`` is invoked, overriding any existing keys.
/// 3. The per-log-statement metadata is merged, overriding any previously set keys.
/// 4. If the log statement carries an error, its `error.message` and `error.type` are merged last.
///
/// Instead of writing to a `TextOutputStream`, each formatted line — including
/// its trailing newline — is delivered to a caller-supplied ``Output``, so the
/// handler can write to stdout, a file, or an in-memory buffer.
///
/// Set ``colorize`` for terminals: the level takes a per-severity color
/// (`trace` gray, `debug` blue, `info` green, `notice` cyan, `warning` yellow,
/// `error` red, `critical` bright red) and the message is bold, while the
/// timestamp and label:source bracket are subdued and tag keys are painted
/// the notice-level cyan against plain separators and values. Brackets in the
/// tags — the enclosing parentheses and any `()`, `[]`, or `{}` pair inside a
/// value — cycle yellow, magenta, and blue by nesting depth, so matching pairs
/// share a color. The stdio factories colorize automatically when attached to
/// a terminal, unless `NO_COLOR` is set.
public struct MachinistLogHandler: LogHandler {
    /// A destination for formatted log lines.
    public struct Output: Sendable {
        /// Invoked once per message with the complete formatted line.
        public let write: @Sendable (String) -> Void

        /// Creates an output that forwards each formatted line to `write`.
        ///
        /// - Parameter write: A closure invoked once per message with the complete
        ///   line, including its trailing newline. Loggers call it from whichever
        ///   thread logs, possibly concurrently — wrap destinations that aren't
        ///   safe for that with ``locked(_:)``.
        public init(write: @escaping @Sendable (String) -> Void) {
            self.write = write
        }
    }

    /// How far to pad the level, label:source, and message columns so the
    /// message and its tags line up across lines.
    ///
    /// Fields longer than their width overflow untouched — padding never
    /// truncates. The timestamp column is fixed-width already, and the tags
    /// trail the message, where a long list wraps its own tail instead of
    /// pushing the message around.
    public struct Justification: Sendable, Equatable {
        /// Width of the `[LEVEL]` column. 10 fits the longest level, `[CRITICAL]`.
        public var level: Int

        /// Width of the `[label:source]` column.
        public var label: Int

        /// Width of the message column. Applied only when tags follow the
        /// message, so lines without tags carry no trailing spaces.
        public var message: Int

        /// Creates a justification with per-column widths. Widths at or below
        /// zero disable padding for that column.
        public init(level: Int = 10, label: Int = 40, message: Int = 40) {
            self.level = max(0, level)
            self.label = max(0, label)
            self.message = max(0, message)
        }

        /// No padding; fields take their natural width.
        public static let none = Justification(level: 0, label: 0, message: 0)
    }

    private let label: String
    private let output: Output

    /// Get the log level configured for this `Logger`.
    ///
    /// > Note: Changing the log level only affects the instance of the `Logger` where you change it.
    public var logLevel: Logger.Level = .info

    /// The metadata provider.
    public var metadataProvider: Logger.MetadataProvider?

    /// Whether to present each line with ANSI escape codes: a per-severity
    /// colored `[LEVEL]`, a bold message, subdued timestamp and
    /// `[label:source]` bracket, notice-cyan tag keys against plain
    /// separators and values, and tag brackets colored by nesting depth.
    ///
    /// Toggling re-styles tags already set on the handler immediately. Off by
    /// default, because color only makes sense when the destination is a
    /// terminal. The ``standardOutput(label:)`` and ``standardError(label:)``
    /// factories detect that case automatically.
    public var colorize: Bool {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata, keyOrder: self.keyOrder)
        }
    }

    /// How far to pad the `[LEVEL]`, `[label:source]`, and message columns. Override with
    /// ``Justification/none`` for the most compact lines.
    public var justification = Justification()

    private var prettyMetadata: String?
    private var keyOrder: [String] = []

    /// Get or set the entire metadata storage as a dictionary.
    public var metadata = Logger.Metadata() {
        didSet {
            self.keyOrder = MachinistLogHandler.reconciledKeyOrder(existing: self.keyOrder, with: self.metadata)
            self.prettyMetadata = self.prettify(self.metadata, keyOrder: self.keyOrder)
        }
    }

    /// Add, change, or remove a logging metadata item.
    ///
    /// > Note: Changing the logging metadata only affects the instance of the `Logger` where you change it.
    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    /// Creates a ``MachinistLogHandler`` that directs its output to `output`,
    /// using the global metadata provider from ``LoggingSystem``.
    ///
    /// - parameters:
    ///   - label: The label for this log handler.
    ///   - output: The destination for formatted log lines.
    ///   - colorize: Whether to color each line's level with ANSI escape codes.
    ///   - justification: How far to pad the `[LEVEL]`, `[label:source]`, and message columns.
    public init(label: String, output: Output, colorize: Bool = false, justification: Justification = Justification()) {
        self.init(label: label, output: output, metadataProvider: LoggingSystem.metadataProvider, colorize: colorize, justification: justification)
    }

    /// Creates a ``MachinistLogHandler`` that directs its output to `output`,
    /// using the metadata provider you provide.
    ///
    /// - parameters:
    ///   - label: The label for this log handler.
    ///   - output: The destination for formatted log lines.
    ///   - metadataProvider: The metadata provider to use, or `nil` for no provider.
    ///   - colorize: Whether to color each line's level with ANSI escape codes.
    ///   - justification: How far to pad the `[LEVEL]`, `[label:source]`, and message columns.
    public init(
        label: String,
        output: Output,
        metadataProvider: Logger.MetadataProvider?,
        colorize: Bool = false,
        justification: Justification = Justification()
    ) {
        self.label = label
        self.output = output
        self.metadataProvider = metadataProvider
        self.colorize = colorize
        self.justification = justification
    }

    /// Log a message using the log level and source that you provide.
    ///
    /// - parameters:
    ///    - event: The log event containing the level, message, metadata, and source location.
    public func log(event: LogEvent) {
        let effectiveMetadata = MachinistLogHandler.prepareMetadata(
            base: self.metadata,
            baseKeyOrder: self.keyOrder,
            provider: self.metadataProvider,
            explicit: event.metadata,
            error: event.error
        )

        let prettyMetadata: String?
        if let (metadata, keyOrder) = effectiveMetadata {
            prettyMetadata = self.prettify(metadata, keyOrder: keyOrder)
        } else {
            prettyMetadata = self.prettyMetadata
        }

        let context = [self.label, event.source].filter { !$0.isEmpty }.joined(separator: ":")
        let columns = [
            self.subdued(self.timestamp()),
            self.subdued("[\(context)]", paddedTo: self.justification.label),
            self.coloredLevel(event.level, paddedTo: self.justification.level),
        ].filter { !$0.isEmpty }

        let message = "\(event.message)"
        let body = prettyMetadata.map { tags in
            let gap = String(repeating: " ", count: max(1, self.justification.message - message.count + 1))
            return "\(self.bolded(message))\(gap)\(self.paintedBracket("(", depth: 0))\(tags)\(self.paintedBracket(")", depth: 0))"
        } ?? self.bolded(message)
        self.output.write("\(columns.joined(separator: " ")) \(body)\n")
    }

    private func subdued(_ text: String) -> String {
        guard self.colorize, !text.isEmpty else {
            return text
        }
        return "\u{1B}[2m\(text)\u{1B}[0m"
    }

    private func bolded(_ text: String) -> String {
        guard self.colorize else {
            return text
        }
        return "\u{1B}[1m\(text)\u{1B}[0m"
    }

    private func subdued(_ text: String, paddedTo width: Int) -> String {
        guard self.colorize, !text.isEmpty else {
            return text.rightPadded(to: width)
        }
        return "\u{1B}[2m\(text.rightPadded(to: width))\u{1B}[0m"
    }

    private func coloredLevel(_ level: Logger.Level, paddedTo width: Int) -> String {
        let padded = "[\(level.rawValue.uppercased())]".rightPadded(to: width)
        guard self.colorize else {
            return padded
        }
        return "\u{1B}[\(level.ansiColorCode)m\(padded)\u{1B}[0m"
    }

    static func prepareMetadata(
        base: Logger.Metadata,
        baseKeyOrder: [String],
        provider: Logger.MetadataProvider?,
        explicit: Logger.Metadata?,
        error: (any Error)?
    ) -> (metadata: Logger.Metadata, keyOrder: [String])? {
        var metadata = base

        let provided = provider?.get() ?? [:]

        guard !provided.isEmpty || !(explicit ?? [:]).isEmpty || error != nil else {
            return nil
        }

        var keyOrder = baseKeyOrder.filter { base[$0] != nil }

        func mergeLayer(_ layer: Logger.Metadata) {
            keyOrder.append(contentsOf: layer.keys.filter { metadata[$0] == nil }.sorted())
            metadata.merge(layer, uniquingKeysWith: { _, override in override })
        }

        if !provided.isEmpty {
            mergeLayer(provided)
        }

        if let explicit, !explicit.isEmpty {
            mergeLayer(explicit)
        }

        if let error {
            keyOrder.append(contentsOf: ["error.message", "error.type"].filter { metadata[$0] == nil })
            metadata["error.message"] = "\(error)"
            metadata["error.type"] = "\(String(reflecting: type(of: error)))"
        }

        return (metadata, keyOrder)
    }

    private func prettify(_ metadata: Logger.Metadata, keyOrder: [String]) -> String? {
        if metadata.isEmpty {
            return nil
        }
        return keyOrder.compactMap { key in
            metadata[key].map { "\(self.styledTagKey(key))\(self.rainbowBracketed("\($0)", depth: 1))" }
        }.joined(separator: ", ")
    }

    private func rainbowBracketed(_ text: String, depth: Int) -> String {
        guard self.colorize else {
            return text
        }
        var expectedClosers: [Character] = []
        var painted = ""
        for character in text {
            if let closer = MachinistLogHandler.closingBrackets[character] {
                painted += self.paintedBracket(character, depth: depth + expectedClosers.count)
                expectedClosers.append(closer)
            } else if character == expectedClosers.last {
                expectedClosers.removeLast()
                painted += self.paintedBracket(character, depth: depth + expectedClosers.count)
            } else {
                painted.append(character)
            }
        }
        return painted
    }

    private func paintedBracket(_ bracket: Character, depth: Int) -> String {
        guard self.colorize else {
            return String(bracket)
        }
        let codes = MachinistLogHandler.rainbowColorCodes
        return "\u{1B}[\(codes[depth % codes.count])m\(bracket)\u{1B}[0m"
    }

    private static let closingBrackets: [Character: Character] = ["(": ")", "[": "]", "{": "}"]

    private static let rainbowColorCodes = [33, 35, 34]

    private func styledTagKey(_ key: String) -> String {
        guard self.colorize else {
            return "\(key): "
        }
        return "\u{1B}[\(Logger.Level.notice.ansiColorCode)m\(key)\u{1B}[0m: "
    }

    static func reconciledKeyOrder(existing: [String], with metadata: Logger.Metadata) -> [String] {
        var order = existing.filter { metadata[$0] != nil }
        let carried = Set(order)
        order.append(contentsOf: metadata.keys.filter { !carried.contains($0) }.sorted())
        return order
    }

    static func terminalSupportsColor(_ descriptor: Int32) -> Bool {
        isatty(descriptor) == 1 && getenv("NO_COLOR") == nil
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        guard let localTime = localtime(&timestamp) else {
            return "<unknown>"
        }
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}

extension Logger.Level {
    fileprivate var ansiColorCode: Int {
        switch self {
        case .trace: return 90
        case .debug: return 34
        case .info: return 32
        case .notice: return 36
        case .warning: return 33
        case .error: return 31
        case .critical: return 91
        }
    }
}

extension String {
    fileprivate func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

extension MachinistLogHandler {
    /// Creates a Machinist log handler that directs its output to STDOUT.
    ///
    /// - parameters:
    ///   - label: The label for this log handler.
    ///   - colorize: Whether to color each line's level with ANSI escape codes.
    ///     Pass `nil` (the default) to colorize only when STDOUT is a terminal
    ///     and the `NO_COLOR` environment variable is unset.
    public static func standardOutput(label: String, colorize: Bool? = nil) -> MachinistLogHandler {
        MachinistLogHandler(
            label: label,
            output: .standardOutput,
            metadataProvider: LoggingSystem.metadataProvider,
            colorize: colorize ?? terminalSupportsColor(STDOUT_FILENO)
        )
    }

    /// Creates a Machinist log handler that directs its output to STDOUT using the metadata provider you provide.
    public static func standardOutput(label: String, metadataProvider: Logger.MetadataProvider?, colorize: Bool? = nil) -> MachinistLogHandler {
        MachinistLogHandler(
            label: label,
            output: .standardOutput,
            metadataProvider: metadataProvider,
            colorize: colorize ?? terminalSupportsColor(STDOUT_FILENO)
        )
    }

    /// Creates a Machinist log handler that directs its output to STDERR.
    ///
    /// - parameters:
    ///   - label: The label for this log handler.
    ///   - colorize: Whether to color each line's level with ANSI escape codes.
    ///     Pass `nil` (the default) to colorize only when STDERR is a terminal
    ///     and the `NO_COLOR` environment variable is unset.
    public static func standardError(label: String, colorize: Bool? = nil) -> MachinistLogHandler {
        MachinistLogHandler(
            label: label,
            output: .standardError,
            metadataProvider: LoggingSystem.metadataProvider,
            colorize: colorize ?? terminalSupportsColor(STDERR_FILENO)
        )
    }

    /// Creates a Machinist log handler that directs its output to STDERR using the metadata provider you provide.
    public static func standardError(label: String, metadataProvider: Logger.MetadataProvider?, colorize: Bool? = nil) -> MachinistLogHandler {
        MachinistLogHandler(
            label: label,
            output: .standardError,
            metadataProvider: metadataProvider,
            colorize: colorize ?? terminalSupportsColor(STDERR_FILENO)
        )
    }
}

private struct StdioFile: @unchecked Sendable {
    var file: UnsafeMutablePointer<FILE>
}

extension MachinistLogHandler.Output {
    /// An output that serializes calls to `write` with a lock.
    ///
    /// Use it for destinations that aren't safe to call from whichever thread
    /// happens to log — writing to a `FileHandle`, mutating shared state, and
    /// so on. The stdio outputs below already lock per write.
    public static func locked(_ write: @escaping @Sendable (String) -> Void) -> Self {
        let lock = NSLock()
        return Self { line in
            lock.withLock { write(line) }
        }
    }

    #if canImport(Darwin)
    /// An output that writes formatted lines to STDOUT, flushing after every write.
    public static let standardOutput = MachinistLogHandler.Output.stdio(Darwin.stdout)

    /// An output that writes formatted lines to STDERR, flushing after every write.
    public static let standardError = MachinistLogHandler.Output.stdio(Darwin.stderr)
    #elseif canImport(Glibc)
    public static let standardOutput = MachinistLogHandler.Output.stdio(Glibc.stdout!)
    public static let standardError = MachinistLogHandler.Output.stdio(Glibc.stderr!)
    #elseif canImport(Musl)
    public static let standardOutput = MachinistLogHandler.Output.stdio(Musl.stdout!)
    public static let standardError = MachinistLogHandler.Output.stdio(Musl.stderr!)
    #endif

    private static func stdio(_ file: UnsafeMutablePointer<FILE>) -> Self {
        let file = StdioFile(file: file)
        return Self { string in
            var string = string
            string.makeContiguousUTF8()
            _ = string.utf8.withContiguousStorageIfAvailable { bytes in
                flockfile(file.file)
                if let base = bytes.baseAddress, !bytes.isEmpty {
                    fwrite(base, 1, bytes.count, file.file)
                }
                funlockfile(file.file)
                fflush(file.file)
            }
        }
    }
}

extension Logger {
    /// Creates a logger that writes formatted lines through a ``MachinistLogHandler``,
    /// using the global metadata provider from ``LoggingSystem``.
    public init(machinistLabel label: String, output: MachinistLogHandler.Output) {
        self.init(label: label) { MachinistLogHandler(label: $0, output: output) }
    }

    /// Creates a logger that writes formatted lines through a ``MachinistLogHandler``,
    /// using the metadata provider you provide.
    public init(machinistLabel label: String, output: MachinistLogHandler.Output, metadataProvider: Logger.MetadataProvider?) {
        self.init(label: label) { MachinistLogHandler(label: $0, output: output, metadataProvider: metadataProvider) }
    }
}
