import Testing
import Logging
import Machinist

@Suite("Sample output")
struct SampleTests {
    @Test("writes sample rows to STDOUT; run with `swift test --filter sampleRows` to eyeball the format")
    func sampleRows() {
        for colorize in [false, true] {
            var log = Logger(label: "com.example.machinist") {
                MachinistLogHandler(
                    label: $0,
                    output: .standardOutput,
                    metadataProvider: Logger.MetadataProvider { ["request-id": "A1B2C3"] },
                    colorize: colorize
                )
            }
            log.logLevel = .trace
            log[metadataKey: "app"] = "machinistd"

            log.trace("entered boot sequence")
            log.debug("loaded 42 cogs from disk")
            log.info("listening on port 9000")
            log.notice("cache is 80% full")
            log.notice("routing request", metadata: ["route": ["boiler", "valve"], "filter": "{psi: [8000, (9000)]}"])
            log.warning("pressure high", metadata: ["psi": "9000"])
            log.error("valve stuck", metadata: ["valve": "main"])
            log.critical("boiler rupture imminent", error: PressureError(), metadata: ["sector": "7"])
        }
    }
}
