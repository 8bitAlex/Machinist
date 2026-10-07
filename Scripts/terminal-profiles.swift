import AppKit

struct Color {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

enum ThemeError: Error, CustomStringConvertible {
    case missingPaletteEntry(Int)
    case missingSetting(String)
    case missingFont(String)

    var description: String {
        switch self {
        case .missingPaletteEntry(let index): "Ghostty theme has no `palette = \(index)=` entry"
        case .missingSetting(let key): "Ghostty theme has no `\(key)` setting"
        case .missingFont(let name): "font `\(name)` isn't installed"
        }
    }
}

struct GhosttyTheme {
    private var palette: [Int: Color] = [:]
    private var settings: [String: Color] = [:]

    init(contentsOf url: URL) throws {
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else {
                continue
            }
            if parts[0] == "palette" {
                let entry = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                if entry.count == 2, let index = Int(entry[0]), let color = Color(hex: entry[1]) {
                    palette[index] = color
                }
            } else if let color = Color(hex: parts[1]) {
                settings[parts[0]] = color
            }
        }
    }

    func ansi(_ index: Int) throws -> Color {
        guard let color = palette[index] else {
            throw ThemeError.missingPaletteEntry(index)
        }
        return color
    }

    func setting(_ key: String) throws -> Color {
        guard let color = settings[key] else {
            throw ThemeError.missingSetting(key)
        }
        return color
    }
}

func itermProfile(from theme: GhosttyTheme) throws -> [String: Any] {
    func component(_ color: Color) -> [String: Any] {
        [
            "Red Component": color.red,
            "Green Component": color.green,
            "Blue Component": color.blue,
            "Alpha Component": 1.0,
            "Color Space": "sRGB",
        ]
    }

    var colors: [String: Color] = [
        "Background Color": try theme.setting("background"),
        "Foreground Color": try theme.setting("foreground"),
        "Bold Color": try theme.setting("foreground"),
        "Cursor Color": try theme.setting("cursor-color"),
        "Cursor Text Color": try theme.setting("cursor-text"),
        "Selection Color": try theme.setting("selection-background"),
        "Selected Text Color": try theme.setting("selection-foreground"),
    ]
    for index in 0..<16 {
        colors["Ansi \(index) Color"] = try theme.ansi(index)
    }

    var profile: [String: Any] = [:]
    for (key, color) in colors {
        for variant in ["", " (Light)", " (Dark)"] {
            profile[key + variant] = component(color)
        }
    }
    return profile
}

func itermDynamicProfile(from theme: GhosttyTheme, named name: String, font: String) throws -> [String: Any] {
    var profile = try itermProfile(from: theme)
    profile["Name"] = name
    profile["Guid"] = "machinist-theme"
    profile["Normal Font"] = font
    profile["Use Separate Colors for Light and Dark Mode"] = true
    return ["Profiles": [profile]]
}

func terminalProfile(from theme: GhosttyTheme, named name: String, fontName: String, fontSize: CGFloat) throws -> [String: Any] {
    func archived(_ color: Color) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
            requiringSecureCoding: true
        )
    }

    var profile: [String: Any] = [
        "name": name,
        "type": "Window Settings",
        "ProfileCurrentVersion": 2.07,
    ]
    for (index, slot) in ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"].enumerated() {
        profile["ANSI\(slot)Color"] = try archived(try theme.ansi(index))
        profile["ANSIBright\(slot)Color"] = try archived(try theme.ansi(index + 8))
    }
    profile["BackgroundColor"] = try archived(try theme.setting("background"))
    profile["TextColor"] = try archived(try theme.setting("foreground"))
    profile["TextBoldColor"] = try archived(try theme.setting("foreground"))
    profile["CursorColor"] = try archived(try theme.setting("cursor-color"))
    profile["SelectionColor"] = try archived(try theme.setting("selection-background"))

    guard let font = NSFont(name: fontName, size: fontSize) else {
        throw ThemeError.missingFont(fontName)
    }
    profile["Font"] = try NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)
    return profile
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    print("wrote \(url.path)")
}

func write(_ plist: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    print("wrote \(url.path)")
}

let ports = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "ports")
let theme = try GhosttyTheme(contentsOf: ports.appending(path: "ghostty/machinist"))
try write(try itermProfile(from: theme), to: ports.appending(path: "iterm2/Machinist.itermcolors"))
try writeJSON(try itermDynamicProfile(from: theme, named: "Machinist", font: "MesloLGSNFM-Regular 13"), to: ports.appending(path: "iterm2/Machinist.json"))
try write(try terminalProfile(from: theme, named: "Machinist", fontName: "MesloLGSNFM-Regular", fontSize: 13), to: ports.appending(path: "terminal/Machinist.terminal"))
