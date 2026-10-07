import Testing
import Logging
import Machinist
import Dispatch

@Suite("MachinistLogHandler")
struct MachinistLogHandlerTests {
    func capture() -> (MachinistLogHandler.Output, Capture) {
        let capture = Capture()
        return (MachinistLogHandler.Output { line in capture.append(line) }, capture)
    }

    @Test("prefixes each line with a local strftime timestamp")
    func timestampFormat() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "boot", output: output)
        log.info("systems nominal")
        #expect(capture.lines.count == 1)
        #expect(capture.lines[0].firstMatch(of: #/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\s/#) != nil)
    }

    @Test("formats justified columns: level, label, source, metadata, then the message")
    func formatsLine() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "boot", output: output)
        log.info("systems nominal")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", label: "boot", message: "systems nominal")])
    }

    @Test("uses the source passed at the call site")
    func explicitSource() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "boot", output: output)
        log.info("systems nominal", source: "ignition")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", label: "boot", source: "ignition", message: "systems nominal")])
    }

    @Test("an empty label drops out of the label:source brackets")
    func emptyLabel() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "", output: output)
        log.info("hello")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", label: "", message: "hello")])
    }

    @Test("respects logLevel")
    func filtersBelowLevel() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "boot", output: output)
        log.debug("too quiet")
        #expect(capture.lines.isEmpty)
    }

    @Test("prints handler metadata when a statement has none of its own")
    func handlerMetadataOnly() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log.logLevel = .debug
        log[metadataKey: "subsystem"] = "engine"
        log.debug("idling")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "debug", metadata: "subsystem: engine", message: "idling")])
    }

    @Test("merges handler and call-site metadata, call-site value wins in its original position")
    func mergesMetadata() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log[metadataKey: "subsystem"] = "engine"
        log[metadataKey: "mode"] = "idle"
        log.warning("pressure high", metadata: ["mode": "steam"])
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "warning", metadata: "subsystem: engine, mode: steam", message: "pressure high")])
    }

    @Test("prints metadata keys in the order they were added, not alphabetically")
    func addedOrder() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log[metadataKey: "zebra"] = "stripes"
        log[metadataKey: "apple"] = "fruit"
        log[metadataKey: "motor"] = "v8"
        log.info("ordered")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", metadata: "zebra: stripes, apple: fruit, motor: v8", message: "ordered")])
    }

    @Test("removing then re-adding a key moves it to the end")
    func removalDropsKey() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log[metadataKey: "zebra"] = "stripes"
        log[metadataKey: "apple"] = "fruit"
        log[metadataKey: "zebra"] = nil
        log[metadataKey: "zebra"] = "dazzle"
        log.info("ordered")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", metadata: "apple: fruit, zebra: dazzle", message: "ordered")])
    }

    @Test("invokes the metadata provider on every statement, overriding handler metadata")
    func mergesProviderMetadata() {
        let (output, capture) = capture()
        let provider = Logger.MetadataProvider { ["region": "eu", "trace-id": "abc123"] }
        var log = Logger(machinistLabel: "api", output: output, metadataProvider: provider)
        log[metadataKey: "region"] = "us"
        log.info("request")
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", label: "api", metadata: "region: eu, trace-id: abc123", message: "request")])
    }

    @Test("call-site metadata wins over the metadata provider")
    func explicitBeatsProvider() {
        let (output, capture) = capture()
        let provider = Logger.MetadataProvider { ["trace-id": "abc123"] }
        let log = Logger(machinistLabel: "api", output: output, metadataProvider: provider)
        log.info("request", metadata: ["trace-id": "override"])
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "info", label: "api", metadata: "trace-id: override", message: "request")])
    }

    @Test("appends error.message and error.type for statements carrying an error")
    func errorMetadata() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "gear", output: output)
        log.error("overpressure", error: PressureError())
        let type = String(reflecting: PressureError.self)
        #expect(capture.lines.map(stripLogTimestamp) == [expectedLine(level: "error", metadata: "error.message: pressure exceeded 9000 PSI, error.type: \(type)", message: "overpressure")])
    }

    @Test("pads columns so the message starts at the same offset on every line")
    func columnsAlign() {
        let (output, capture) = capture()
        var first = Logger(machinistLabel: "gear", output: output)
        first[metadataKey: "a"] = "1"
        first.info("first")
        var second = Logger(machinistLabel: "gear", output: output)
        second[metadataKey: "alpha"] = "1234567"
        second.info("second")
        let messageColumns = [
            capture.lines[0].firstRange(of: " first")!.lowerBound,
            capture.lines[1].firstRange(of: " second")!.lowerBound,
        ]
        #expect(messageColumns[0] == messageColumns[1])
    }

    @Test("long tag lists trail the message in parentheses without shifting its column")
    func longMetadataTrails() {
        let (output, capture) = capture()
        var first = Logger(machinistLabel: "gear", output: output)
        first[metadataKey: "a"] = "1"
        first.info("first")
        let long = String(repeating: "x", count: 60)
        var second = Logger(machinistLabel: "gear", output: output)
        second[metadataKey: "long"] = "\(long)"
        second.info("second")
        let messageColumns = [
            capture.lines[0].firstRange(of: " first")!.lowerBound,
            capture.lines[1].firstRange(of: " second")!.lowerBound,
        ]
        #expect(messageColumns[0] == messageColumns[1])
        #expect(capture.lines[1].hasSuffix("\(tagGap(after: "second"))(long: \(long))\n"))
    }

    @Test("justification.none restores the compact layout")
    func unjustified() {
        let (output, capture) = capture()
        let log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, justification: .none) }
        log.info("systems nominal")
        #expect(capture.lines.map(stripLogTimestamp) == ["[gear:MachinistTests] [INFO] systems nominal\n"])
    }

    @Test("pads the message so tags start at the same column whatever the message length")
    func tagsAlign() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log[metadataKey: "app"] = "machinistd"
        log.info("cache is 80% full")
        log.info("entered boot sequence")
        let tagColumns = capture.lines.map { $0.firstRange(of: "(app")!.lowerBound.utf16Offset(in: $0) }
        #expect(tagColumns[0] == tagColumns[1])
    }

    @Test("a message wider than its column overflows with a single space before the tags")
    func longMessageOverflows() {
        let (output, capture) = capture()
        var log = Logger(machinistLabel: "gear", output: output)
        log[metadataKey: "app"] = "machinistd"
        let long = String(repeating: "x", count: 50)
        log.info("\(long)")
        #expect(capture.lines[0].hasSuffix(" \(long) (app: machinistd)\n"))
    }

    @Test("lines without tags carry no trailing padding")
    func untaggedLinesAreNotPadded() {
        let (output, capture) = capture()
        let log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil) }
        log.info("idling")
        #expect(capture.lines[0].hasSuffix(" idling\n"))
    }

    @Test("justification.none separates the message from its tags with a single space")
    func unjustifiedTags() {
        let (output, capture) = capture()
        var log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, justification: .none) }
        log[metadataKey: "app"] = "machinistd"
        log.info("idling")
        #expect(capture.lines.map(stripLogTimestamp) == ["[gear:MachinistTests] [INFO] idling (app: machinistd)\n"])
    }

    @Test("colorize wraps the level in that level's ANSI escape code", arguments: [
        (Logger.Level.trace, 90),
        (.debug, 34),
        (.info, 32),
        (.notice, 36),
        (.warning, 33),
        (.error, 31),
        (.critical, 91),
    ])
    func colorizedLevels(level: Logger.Level, code: Int) {
        let (output, capture) = capture()
        var log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log.logLevel = .trace
        log.log(level: level, "engine engaged")
        #expect(capture.lines[0].contains("\u{1B}[\(code)m[\(level.rawValue.uppercased())]"))
    }

    @Test("colorize subdues the furniture, tints the level, and bolds the message")
    func subduedParts() {
        let (output, capture) = capture()
        let log = Logger(label: "boot") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log.info("systems nominal")
        let line = capture.lines[0]
        let level = "\u{1B}[32m\(pad("[INFO]", 10))\u{1B}[0m"
        let context = "\u{1B}[2m\(pad("[boot:MachinistTests]", 40))\u{1B}[0m"
        let expected = "\(context) \(level) \u{1B}[1msystems nominal\u{1B}[0m\n"
        #expect(line.hasPrefix("\u{1B}[2m"))
        #expect(stripLogTimestamp(line) == expected)
    }

    @Test("colorize paints tag keys notice-cyan against plain separators and values")
    func colorizedTagKeys() {
        let (output, capture) = capture()
        var log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log[metadataKey: "subsystem"] = "engine"
        log.info("idling", metadata: ["mode": "idle"])
        let tags = ["subsystem", "mode"].map(styledTagKey)
        let (open, close) = (rainbowBracket("(", depth: 0), rainbowBracket(")", depth: 0))
        #expect(capture.lines[0].hasSuffix("\(tagGap(after: "idling"))\(open)\(tags[0])engine, \(tags[1])idle\(close)\n"))
    }

    @Test("colorize paints tag brackets by nesting depth, matching pairs alike")
    func rainbowBrackets() {
        let (output, capture) = capture()
        let log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log.info("routing", metadata: ["route": "{a: [b(c)], d: [e]}"])
        let b = rainbowBracket
        let route = "\(b("{", 1))a: \(b("[", 2))b\(b("(", 3))c\(b(")", 3))\(b("]", 2)), d: \(b("[", 2))e\(b("]", 2))\(b("}", 1))"
        #expect(capture.lines[0].hasSuffix("\(tagGap(after: "routing"))\(b("(", 0))\(styledTagKey("route"))\(route)\(b(")", 0))\n"))
    }

    @Test("a closing bracket that doesn't match the innermost open one stays plain")
    func mismatchedBracketsStayPlain() {
        let (output, capture) = capture()
        let log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log.info("routing", metadata: ["route": "(a]"])
        let b = rainbowBracket
        #expect(capture.lines[0].hasSuffix("\(tagGap(after: "routing"))\(b("(", 0))\(styledTagKey("route"))\(b("(", 1))a]\(b(")", 0))\n"))
    }

    @Test("structured metadata values get rainbow brackets too")
    func rainbowStructuredValues() {
        let (output, capture) = capture()
        let log = Logger(label: "gear") { MachinistLogHandler(label: $0, output: output, metadataProvider: nil, colorize: true) }
        log.info("routing", metadata: ["hops": ["a", "b"]])
        let b = rainbowBracket
        let hops = "\(b("[", 1))\"a\", \"b\"\(b("]", 1))"
        #expect(capture.lines[0].hasSuffix("\(tagGap(after: "routing"))\(b("(", 0))\(styledTagKey("hops"))\(hops)\(b(")", 0))\n"))
    }

    @Test("toggling colorize recolors tags already set on the handler")
    func colorizeToggleRecolorsCache() {
        let (output, capture) = capture()
        var handler = MachinistLogHandler(label: "gear", output: output, metadataProvider: nil)
        handler[metadataKey: "subsystem"] = "engine"
        handler.colorize = true
        let log = Logger(label: "gear") { _ in handler }
        log.info("idling")
        let (open, close) = (rainbowBracket("(", depth: 0), rainbowBracket(")", depth: 0))
        #expect(capture.lines[0].hasSuffix("\(tagGap(after: "idling"))\(open)\(styledTagKey("subsystem"))engine\(close)\n"))
    }

    @Test("levels are plain without colorize")
    func plainLevels() {
        let (output, capture) = capture()
        let log = Logger(machinistLabel: "gear", output: output)
        log.warning("pressure high")
        #expect(!capture.lines[0].contains("\u{1B}"))
    }

    @Test("locked outputs serialize concurrent writes")
    func lockedOutputSerializes() {
        let capture = UnsafeCapture()
        let output = MachinistLogHandler.Output.locked { line in capture.append(line) }
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            output.write("line \(i)\n")
        }
        #expect(capture.lines.count == 100)
        #expect(capture.lines.allSatisfy { $0.hasPrefix("line ") && $0.hasSuffix("\n") })
    }

    @Test("treats log level and metadata as values")
    func valueSemantics() {
        let (output, _) = capture()
        var logger1 = Logger(machinistLabel: "first", output: output)
        logger1.logLevel = .debug
        logger1[metadataKey: "only-on"] = "first"

        var logger2 = logger1
        logger2.logLevel = .error
        logger2[metadataKey: "only-on"] = "second"

        #expect(logger1.logLevel == .debug)
        #expect(logger2.logLevel == .error)
        #expect(logger1[metadataKey: "only-on"] == "first")
        #expect(logger2[metadataKey: "only-on"] == "second")
    }
}
