#!/usr/bin/env swift

import Foundation
import IOKit.hid

// MARK: - Color Formatter for Terminal Output

enum Color {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let green = "\u{001B}[32m"
    static let red = "\u{001B}[31m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let cyan = "\u{001B}[36m"
    static let gray = "\u{001B}[90m"
    static let magenta = "\u{001B}[35m"
}

// MARK: - Notify Setting Model

enum NotifySetting: Codable, CustomStringConvertible {
    case enabled
    case disabled
    case custom(String)

    var description: String {
        switch self {
        case .enabled: return "yes"
        case .disabled: return "no"
        case .custom(let s): return s
        }
    }

    var isEnabled: Bool {
        switch self {
        case .enabled, .custom: return true
        case .disabled: return false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = b ? .enabled : .disabled
            return
        }
        if let s = try? container.decode(String.self) {
            let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "true" || lower == "yes" || lower == "1" {
                self = .enabled
            } else if lower == "false" || lower == "no" || lower == "0" {
                self = .disabled
            } else {
                self = .custom(s)
            }
            return
        }
        self = .disabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled: try container.encode(true)
        case .disabled: try container.encode(false)
        case .custom(let s): try container.encode(s)
        }
    }
}

// MARK: - Trigger Mode Model

enum TriggerMode: String, Codable, CustomStringConvertible {
    case enter
    case exit
    case closing
    case opening
    case change

    var description: String {
        switch self {
        case .enter: return "enter"
        case .exit: return "exit"
        case .closing: return "closing"
        case .opening: return "opening"
        case .change: return "change"
        }
    }

    static func parse(_ str: String) -> TriggerMode {
        let lower = str.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "exit", "leave", "outside": return .exit
        case "close", "closing", "down": return .closing
        case "open", "opening", "up": return .opening
        case "change", "both", "all": return .change
        default: return .enter
        }
    }
}

// MARK: - Angle Condition Model

enum AngleCondition: Codable, CustomStringConvertible {
    case below(Double)
    case above(Double)
    case range(Double, Double)
    case exact(Double)

    var description: String {
        switch self {
        case .below(let v): return "<\(formatAngle(v))"
        case .above(let v): return ">\(formatAngle(v))"
        case .range(let min, let max): return "\(formatAngle(min))-\(formatAngle(max))"
        case .exact(let v): return "=\(formatAngle(v))"
        }
    }

    var displayString: String {
        switch self {
        case .below(let v): return "< \(formatAngle(v))°"
        case .above(let v): return "> \(formatAngle(v))°"
        case .range(let min, let max): return "\(formatAngle(min))° - \(formatAngle(max))°"
        case .exact(let v): return "= \(formatAngle(v))°"
        }
    }

    private func formatAngle(_ val: Double) -> String {
        return (val == floor(val)) ? String(Int(val)) : String(format: "%.1f", val)
    }

    func matches(angle: Double) -> Bool {
        switch self {
        case .below(let v): return angle <= v
        case .above(let v): return angle >= v
        case .range(let min, let max): return angle >= min && angle <= max
        case .exact(let v): return abs(angle - v) < 1.0
        }
    }

    func defaultRearm() -> Double {
        switch self {
        case .below(let v): return min(180.0, v + 5.0)
        case .above(let v): return max(0.0, v - 5.0)
        case .range(_, let max): return min(180.0, max + 5.0)
        case .exact(let v): return v + 5.0
        }
    }

    static func parse(_ str: String) -> AngleCondition? {
        let trimmed = str.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "°", with: "")
        if trimmed.hasPrefix("<=") {
            if let v = Double(trimmed.dropFirst(2)) { return .below(v) }
        } else if trimmed.hasPrefix("<") {
            if let v = Double(trimmed.dropFirst(1)) { return .below(v) }
        } else if trimmed.hasPrefix(">=") {
            if let v = Double(trimmed.dropFirst(2)) { return .above(v) }
        } else if trimmed.hasPrefix(">") {
            if let v = Double(trimmed.dropFirst(1)) { return .above(v) }
        } else if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return .range(parts[0], parts[1]) }
        } else if trimmed.contains("..") {
            let parts = trimmed.components(separatedBy: "..").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return .range(parts[0], parts[1]) }
        } else if let v = Double(trimmed) {
            return .below(v)
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self), let cond = AngleCondition.parse(str) {
            self = cond
            return
        }
        if let num = try? container.decode(Double.self) {
            self = .below(num)
            return
        }
        if let arr = try? container.decode([Double].self), arr.count >= 2 {
            self = .range(arr[0], arr[1])
            return
        }
        if let dict = try? container.decode([String: Double].self) {
            if let min = dict["min"], let max = dict["max"] {
                self = .range(min, max)
                return
            }
            if let below = dict["below"] ?? dict["threshold"] {
                self = .below(below)
                return
            }
            if let above = dict["above"] {
                self = .above(above)
                return
            }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid angle format")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Filter Rules Model

struct FilterRules: Codable {
    var time: String?
    var cooldown: Double?
    var rearm: Double?
    var days: [String]?

    enum CodingKeys: String, CodingKey {
        case time
        case cooldown
        case rearm
        case days
    }

    init(time: String? = nil, cooldown: Double? = 5.0, rearm: Double? = nil, days: [String]? = nil) {
        self.time = time
        self.cooldown = cooldown
        self.rearm = rearm
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try? container.decode(String.self, forKey: .time)
        cooldown = try? container.decode(Double.self, forKey: .cooldown)
        rearm = try? container.decode(Double.self, forKey: .rearm)

        if let daysArray = try? container.decode([String].self, forKey: .days) {
            days = daysArray
        } else if let daysStr = try? container.decode(String.self, forKey: .days) {
            days = daysStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            days = nil
        }
    }

    func check(now: Date = Date()) -> (allowed: Bool, reason: String?) {
        // 1. Time check
        if let timeStr = time, !timeStr.isEmpty {
            if let range = TimeHelper.parseTimeRange(timeStr) {
                if !TimeHelper.isTimeActive(range: range, date: now) {
                    return (false, "Outside allowed time range: \(timeStr)")
                }
            }
        }

        // 2. Day check
        if let dayList = days, !dayList.isEmpty {
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: now)
            let daySymbols = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            let currentDaySymbol = daySymbols[weekday - 1]
            let isWeekend = (weekday == 1 || weekday == 7)

            let matched = dayList.contains { d in
                let norm = d.lowercased().trimmingCharacters(in: .whitespaces)
                if norm == "weekdays" { return !isWeekend }
                if norm == "weekends" { return isWeekend }
                return norm == currentDaySymbol || norm.hasPrefix(currentDaySymbol)
            }

            if !matched {
                return (false, "Not scheduled for today (\(currentDaySymbol.uppercased()))")
            }
        }

        return (true, nil)
    }

    var summary: String {
        var parts: [String] = []
        if let t = time, !t.isEmpty { parts.append("time: \(t)") }
        if let d = days, !d.isEmpty { parts.append("days: \(d.joined(separator: ","))") }
        if let cd = cooldown { parts.append("cd: \(Int(cd))s") }
        if let r = rearm { parts.append("rearm: \(Int(r))°") }
        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }
}

// MARK: - Automation Entry

struct AutomationEntry: Codable {
    var name: String
    var angle: AngleCondition
    var script: String
    var enabled: Bool
    var notify: NotifySetting?
    var trigger: TriggerMode?
    var rules: FilterRules?

    enum CodingKeys: String, CodingKey {
        case name
        case angle
        case script
        case enabled
        case notify
        case trigger
        case rules
    }

    init(name: String, angle: AngleCondition, script: String, enabled: Bool = true, notify: NotifySetting? = .enabled, trigger: TriggerMode? = .enter, rules: FilterRules? = nil) {
        self.name = name
        self.angle = angle
        self.script = script
        self.enabled = enabled
        self.notify = notify
        self.trigger = trigger
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        script = try container.decode(String.self, forKey: .script)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
        notify = try? container.decode(NotifySetting.self, forKey: .notify)
        trigger = try? container.decode(TriggerMode.self, forKey: .trigger)
        rules = try? container.decode(FilterRules.self, forKey: .rules)

        // Try decoding angle, with fallback to trigger field if used as angle condition
        if let parsedAngle = try? container.decode(AngleCondition.self, forKey: .angle) {
            angle = parsedAngle
        } else if let triggerStr = try? container.decode(String.self, forKey: .trigger),
                  let parsedAngle = AngleCondition.parse(triggerStr) {
            angle = parsedAngle
            trigger = .enter
        } else {
            throw DecodingError.dataCorruptedError(forKey: .angle, in: container, debugDescription: "Missing or invalid 'angle' parameter")
        }
    }
}

// MARK: - Time Helper

enum TimeHelper {
    static func parseTimeComponent(_ str: String) -> Int? {
        let cleaned = str.trimmingCharacters(in: .whitespaces).lowercased()
        let isPM = cleaned.contains("pm")
        let isAM = cleaned.contains("am")
        let digitsOnly = cleaned.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces)
        let parts = digitsOnly.split(separator: ":").map { String($0) }
        guard let h = Int(parts[0]) else { return nil }
        let m = (parts.count > 1 ? Int(parts[1]) : 0) ?? 0
        var hour = h
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        return hour * 60 + m
    }

    static func parseTimeRange(_ str: String) -> (start: Int, end: Int)? {
        let parts = str.components(separatedBy: "-")
        guard parts.count == 2,
              let s = parseTimeComponent(parts[0]),
              let e = parseTimeComponent(parts[1]) else { return nil }
        return (s, e)
    }

    static func isTimeActive(range: (start: Int, end: Int), date: Date = Date()) -> Bool {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let cur = h * 60 + m
        if range.start <= range.end {
            return cur >= range.start && cur <= range.end
        } else {
            return cur >= range.start || cur <= range.end
        }
    }
}

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    let logFileURL: URL
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    var echoToStdout: Bool = false

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".lid-automation")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("events.log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func log(level: String, message: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [\(level)] \(message)\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
            try? fileHandle?.synchronize()
        }

        if echoToStdout {
            let color: String
            switch level {
            case "TRIGGER": color = Color.green + Color.bold
            case "NOTIFY":  color = Color.magenta + Color.bold
            case "SUCCESS": color = Color.green
            case "SKIPPED": color = Color.yellow
            case "ERROR":   color = Color.red + Color.bold
            default:        color = Color.cyan
            }
            print("\(Color.gray)[\(ts)]\(Color.reset) \(color)[\(level)]\(Color.reset) \(message)")
        }
    }

    func view(lines: Int = 30, follow: Bool = false) {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else {
            print("No log file found at \(logFileURL.path)")
            return
        }

        if follow {
            print("📡 Following logs at \(logFileURL.path) (Ctrl+C to stop)...")
            let p = Process()
            p.launchPath = "/usr/bin/tail"
            p.arguments = ["-n", "\(lines)", "-f", logFileURL.path]
            p.launch()
            p.waitUntilExit()
        } else {
            let p = Process()
            p.launchPath = "/usr/bin/tail"
            p.arguments = ["-n", "\(lines)", logFileURL.path]
            p.launch()
            p.waitUntilExit()
        }
    }

    func clear() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        print("🧹 Logs cleared at \(logFileURL.path)")
    }

    var logPath: String { logFileURL.path }
}

// MARK: - Script Runner & Notifier

final class ScriptRunner {
    typealias SACLockScreenImmediateFunc = @convention(c) () -> Void
    typealias DisplayServicesSetBrightnessFunc = @convention(c) (UInt32, Float) -> Int32

    static func sendNotification(title: String, subtitle: String, message: String) {
        let cleanTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let cleanSub = subtitle.replacingOccurrences(of: "\"", with: "\\\"")
        let cleanMsg = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(cleanMsg)\" with title \"\(cleanTitle)\" subtitle \"\(cleanSub)\""
        _ = runCommand("/usr/bin/osascript -e '\(script)'")
    }

    static func executeAction(script: String, entryName: String, angle: Double = 0.0, prevAngle: Double = 0.0) -> (exitCode: Int32, output: String) {
        let trimmed = script.trimmingCharacters(in: .whitespaces)

        if trimmed == "lock" || trimmed == "builtin:lock" {
            lockScreen()
            return (0, "Screen locked")
        }

        if trimmed == "mute" || trimmed == "builtin:mute" {
            return runCommand("/usr/bin/osascript -e 'set volume output muted true'")
        }

        if trimmed == "unmute" || trimmed == "builtin:unmute" {
            return runCommand("/usr/bin/osascript -e 'set volume output muted false'")
        }

        if trimmed.hasPrefix("builtin:volume") || trimmed.hasPrefix("volume") {
            let parts = trimmed.split(separator: " ")
            let level = (parts.count > 1 ? Int(parts[1]) : 50) ?? 50
            let cmd = "/usr/bin/osascript -e 'set volume output volume \(level)'"
            return runCommand(cmd)
        }

        if trimmed.hasPrefix("builtin:brightness") || trimmed.hasPrefix("brightness") {
            let parts = trimmed.split(separator: " ")
            let level = (parts.count > 1 ? Float(parts[1]) : 80.0) ?? 80.0
            setBrightness(percentage: level)
            return (0, "Display brightness set to \(Int(level))%")
        }

        if trimmed == "builtin:beep" || trimmed == "beep" {
            let cmd = "/usr/bin/osascript -e 'beep'"
            return runCommand(cmd)
        }

        if trimmed.hasPrefix("builtin:sound") {
            let parts = trimmed.split(separator: " ")
            let sound = (parts.count > 1 ? String(parts[1]) : "Ping")
            let cmd = "/usr/bin/afplay /System/Library/Sounds/\(sound).aiff"
            return runCommand(cmd)
        }

        if trimmed == "sleep" || trimmed == "builtin:sleep" {
            return runCommand("/usr/bin/osascript -e 'tell application \"System Events\" to sleep'")
        }

        if trimmed == "displaysleep" || trimmed == "builtin:displaysleep" {
            return runCommand("/usr/bin/pmset displaysleepnow")
        }

        return runCommand(script, angle: angle, prevAngle: prevAngle, ruleName: entryName)
    }

    static func run(entry: AutomationEntry, angle: Double, prevAngle: Double) {
        Logger.shared.log(level: "TRIGGER", message: "Rule '\(entry.name)' -> Executing: \(entry.script)")

        // Send macOS notification if configured
        if let notify = entry.notify, notify.isEnabled {
            let notifMsg: String
            switch notify {
            case .custom(let customMsg):
                notifMsg = customMsg
            default:
                notifMsg = "Lid angle: \(String(format: "%.1f°", angle)) • Action executed"
            }
            sendNotification(title: "Lid Automator", subtitle: entry.name, message: notifMsg)
            Logger.shared.log(level: "NOTIFY", message: "Sent notification: \(notifMsg)")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let (status, output) = executeAction(script: entry.script, entryName: entry.name, angle: angle, prevAngle: prevAngle)
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

            if status == 0 {
                let trimmedOut = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = trimmedOut.isEmpty ? "" : " | Output: \(trimmedOut)"
                Logger.shared.log(level: "SUCCESS", message: "Rule '\(entry.name)' finished in \(elapsedMs)ms (exit: 0)\(detail)")
            } else {
                Logger.shared.log(level: "ERROR", message: "Rule '\(entry.name)' failed in \(elapsedMs)ms (exit: \(status)) | Error: \(output)")
            }
        }
    }

    static func lockScreen() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            let lockFunc = unsafeBitCast(sym, to: SACLockScreenImmediateFunc.self)
            lockFunc()
            return
        }
        _ = runCommand("/usr/bin/pmset displaysleepnow")
    }

    static func setBrightness(percentage: Float) {
        let clamped = max(0.0, min(100.0, percentage)) / 100.0
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
           let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            let setB = unsafeBitCast(sym, to: DisplayServicesSetBrightnessFunc.self)
            _ = setB(1, clamped)
        }
    }

    static func runCommand(_ command: String, angle: Double = 0.0, prevAngle: Double = 0.0, ruleName: String = "") -> (exitCode: Int32, output: String) {
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        env["LID_ANGLE"] = String(format: "%.1f", angle)
        env["LID_PREV_ANGLE"] = String(format: "%.1f", prevAngle)
        env["LID_RULE_NAME"] = ruleName
        env["LID_TIMESTAMP"] = String(Int(Date().timeIntervalSince1970))
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

// MARK: - Configuration Manager

final class ConfigManager {
    static var shared = ConfigManager()
    var configURL: URL

    static var defaultDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".lid-automation")
    }

    static var defaultConfigURL: URL {
        return defaultDir.appendingPathComponent("config")
    }

    static var chosenPointerURL: URL {
        return defaultDir.appendingPathComponent("config_path")
    }

    init(customPath: String? = nil) {
        let dir = Self.defaultDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let custom = customPath {
            configURL = URL(fileURLWithPath: (custom as NSString).isAbsolutePath ? custom : "\(FileManager.default.currentDirectoryPath)/\(custom)")
        } else if let savedPointer = try? String(contentsOf: Self.chosenPointerURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  !savedPointer.isEmpty,
                  FileManager.default.fileExists(atPath: savedPointer) {
            configURL = URL(fileURLWithPath: savedPointer)
        } else if FileManager.default.fileExists(atPath: Self.defaultConfigURL.path) {
            configURL = Self.defaultConfigURL
        } else if FileManager.default.fileExists(atPath: "\(FileManager.default.currentDirectoryPath)/automations.json") {
            configURL = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/automations.json")
        } else {
            configURL = Self.defaultConfigURL
        }
    }

    func setChosenConfigPath(_ path: String) {
        let abs = (path as NSString).isAbsolutePath ? path : "\(FileManager.default.currentDirectoryPath)/\(path)"
        try? abs.write(to: Self.chosenPointerURL, atomically: true, encoding: .utf8)
        configURL = URL(fileURLWithPath: abs)
    }

    func resetToDefaultConfigPath() {
        try? FileManager.default.removeItem(at: Self.chosenPointerURL)
        configURL = Self.defaultConfigURL
    }

    func loadEntriesWithResult() -> Result<[AutomationEntry], Error> {
        var pathsToTry = [configURL]
        if configURL != Self.defaultConfigURL {
            pathsToTry.append(Self.defaultConfigURL)
        }
        let local = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/automations.json")
        if !pathsToTry.contains(local) {
            pathsToTry.append(local)
        }

        for path in pathsToTry {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            do {
                let data = try Data(contentsOf: path)
                if let entries = try? JSONDecoder().decode([AutomationEntry].self, from: data) {
                    return .success(entries)
                }
                struct Wrapper: Codable { let rules: [AutomationEntry] }
                if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data) {
                    return .success(wrapped.rules)
                }
                _ = try JSONDecoder().decode([AutomationEntry].self, from: data)
            } catch {
                return .failure(error)
            }
        }
        return .success([])
    }

    func loadEntries() -> [AutomationEntry] {
        if case .success(let entries) = loadEntriesWithResult() {
            return entries
        }
        return []
    }

    func saveEntries(_ entries: [AutomationEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(entries)
            try data.write(to: configURL)

            // Mirror to default ~/.lid-automation/config if custom file is used
            if configURL != Self.defaultConfigURL {
                try? data.write(to: Self.defaultConfigURL)
            }
        } catch {
            print("❌ Failed to save config: \(error)")
        }
    }

    func addEntry(_ entry: AutomationEntry) {
        var list = loadEntries()
        list.append(entry)
        saveEntries(list)
    }

    func removeEntry(at index: Int) -> Bool {
        var list = loadEntries()
        guard index >= 0 && index < list.count else { return false }
        list.remove(at: index)
        saveEntries(list)
        return true
    }

    func toggleEntry(at index: Int, enabled: Bool) -> Bool {
        var list = loadEntries()
        guard index >= 0 && index < list.count else { return false }
        list[index].enabled = enabled
        saveEntries(list)
        return true
    }

    func findIndex(query: String) -> Int? {
        let list = loadEntries()
        if let idx = Int(query), idx >= 1 && idx <= list.count {
            return idx - 1
        }
        let lower = query.lowercased()
        return list.firstIndex { $0.name.lowercased().contains(lower) }
    }
}

// MARK: - Config File Watcher (Hot-Reload)

final class ConfigFileWatcher {
    private var lastModificationDate: Date?
    private var lastContentHash: Int?
    private var currentConfigPath: String = ""
    private var lastPointerDate: Date?
    private var timer: Timer?
    var onReload: (([AutomationEntry]) -> Void)?

    init() {
        recordCurrentState()
    }

    private func recordCurrentState() {
        currentConfigPath = ConfigManager.shared.configURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: currentConfigPath),
           let mdate = attrs[.modificationDate] as? Date {
            lastModificationDate = mdate
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: currentConfigPath)) {
            lastContentHash = data.hashValue
        }
        let pointerPath = ConfigManager.chosenPointerURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: pointerPath),
           let mdate = attrs[.modificationDate] as? Date {
            lastPointerDate = mdate
        }
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.current.add(timer, forMode: .default)
        self.timer = timer
    }

    func check() {
        var needsReload = false

        // 1. Check if chosen config pointer changed
        let pointerPath = ConfigManager.chosenPointerURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: pointerPath),
           let mdate = attrs[.modificationDate] as? Date {
            if lastPointerDate == nil || mdate != lastPointerDate {
                lastPointerDate = mdate
                ConfigManager.shared = ConfigManager()
                let newPath = ConfigManager.shared.configURL.path
                if newPath != currentConfigPath {
                    currentConfigPath = newPath
                    needsReload = true
                }
            }
        }

        // 2. Check if active config file was modified
        if let attrs = try? FileManager.default.attributesOfItem(atPath: currentConfigPath),
           let mdate = attrs[.modificationDate] as? Date {
            if lastModificationDate == nil || mdate != lastModificationDate {
                lastModificationDate = mdate
                if let data = try? Data(contentsOf: URL(fileURLWithPath: currentConfigPath)) {
                    let hash = data.hashValue
                    if hash != lastContentHash {
                        lastContentHash = hash
                        needsReload = true
                    }
                }
            }
        }

        if needsReload {
            switch ConfigManager.shared.loadEntriesWithResult() {
            case .success(let newEntries):
                onReload?(newEntries)
            case .failure(let error):
                Logger.shared.log(level: "ERROR", message: "⚠️ Config file modified on disk, but invalid JSON: \(error.localizedDescription). Keeping existing rules in memory.")
            }
        }
    }
}

// MARK: - Rule Runtime State

final class ActiveRuleState {
    let entry: AutomationEntry
    var isArmed: Bool = false
    var lastTriggered: Date = .distantPast

    init(entry: AutomationEntry) {
        self.entry = entry
    }

    func evaluate(angle: Double, prevAngle: Double) {
        guard entry.enabled else { return }

        let now = Date()
        let cooldown = entry.rules?.cooldown ?? 5.0
        let rearm = entry.rules?.rearm ?? entry.angle.defaultRearm()
        let triggerMode = entry.trigger ?? .enter

        let isMatching = entry.angle.matches(angle: angle)
        let wasMatching = (prevAngle >= 0) ? entry.angle.matches(angle: prevAngle) : isMatching

        var shouldTrigger = false
        switch triggerMode {
        case .enter:
            shouldTrigger = (!wasMatching && isMatching) || (isArmed && isMatching)
        case .exit:
            shouldTrigger = (wasMatching && !isMatching)
        case .closing:
            shouldTrigger = ((!wasMatching && isMatching) || (isArmed && isMatching)) && (prevAngle > angle)
        case .opening:
            shouldTrigger = ((!wasMatching && isMatching) || (isArmed && isMatching)) && (prevAngle < angle)
        case .change:
            shouldTrigger = (wasMatching != isMatching)
        }

        if shouldTrigger {
            let timeSinceLast = now.timeIntervalSince(lastTriggered)
            if timeSinceLast < cooldown {
                let remaining = String(format: "%.1f", cooldown - timeSinceLast)
                Logger.shared.log(level: "SKIPPED", message: "Rule '\(entry.name)' matched but on cooldown (\(remaining)s left)")
                return
            }

            // Check filter rules (time range, days)
            if let rules = entry.rules {
                let check = rules.check(now: now)
                if !check.allowed {
                    Logger.shared.log(level: "SKIPPED", message: "Rule '\(entry.name)' matched but skipped: \(check.reason ?? "rule filtered")")
                    return
                }
            }

            // Fire action and notification!
            ScriptRunner.run(entry: entry, angle: angle, prevAngle: prevAngle)
            lastTriggered = now
            isArmed = false
        } else if !isMatching {
            // Check hysteresis re-arm condition
            var shouldArm = false
            switch entry.angle {
            case .below:
                if angle >= rearm { shouldArm = true }
            case .above:
                if angle <= rearm { shouldArm = true }
            case .range, .exact:
                shouldArm = true
            }

            if shouldArm && !isArmed {
                isArmed = true
                Logger.shared.log(level: "INFO", message: "Rule '\(entry.name)' is now ARMED at \(String(format: "%.1f°", angle)) (trigger: \(triggerMode.description), target: \(entry.angle.displayString))")
            }
        }
    }
}

// MARK: - Lid Sensor Reader

final class LidSensorReader {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var onAngleChange: ((Double, Double) -> Void)?
    private(set) var lastAngle: Double = -1.0

    init?() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matchingCriteria: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDProductIDKey as String: 0x8104,
                kIOHIDPrimaryUsagePageKey as String: 0x0020,
                kIOHIDPrimaryUsageKey as String: 0x008A,
            ],
            [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDPrimaryUsagePageKey as String: 0x0020,
                kIOHIDPrimaryUsageKey as String: 0x008A,
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return nil }

        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for candidate in devices {
            if IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess {
                self.device = candidate
                break
            }
        }

        guard self.device != nil else {
            IOHIDManagerClose(manager, 0)
            return nil
        }
    }

    deinit {
        if let device = device { IOHIDDeviceClose(device, 0) }
        IOHIDManagerClose(manager, 0)
        buffer.deallocate()
    }

    func readCurrentAngle() -> Double? {
        guard let device = device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let angle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
        return (0...180).contains(angle) ? angle : nil
    }

    func startStreaming() {
        guard let device = device else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()

        // 1. Hardware input report callback
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, sender, type, reportId, report, length in
            guard let context = context, result == kIOReturnSuccess, length >= 3 else { return }
            let this = Unmanaged<LidSensorReader>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            let angle = Double(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
            guard (0...180).contains(angle) else { return }

            if this.lastAngle < 0 || abs(angle - this.lastAngle) >= 0.2 {
                let prev = this.lastAngle
                this.lastAngle = angle
                this.onAngleChange?(angle, prev)
            }
        }, context)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // 2. Hybrid polling fallback watchdog (100ms)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let angle = self.readCurrentAngle() {
                if self.lastAngle < 0 || abs(angle - self.lastAngle) >= 0.2 {
                    let prev = self.lastAngle
                    self.lastAngle = angle
                    self.onAngleChange?(angle, prev)
                }
            }
        }
        RunLoop.current.add(timer, forMode: .default)

        CFRunLoopRun()
    }
}

// MARK: - Daemon Manager (LaunchAgent)

enum DaemonManager {
    static let label = "com.user.lid-automator"

    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func start() {
        stop()
        Thread.sleep(forTimeInterval: 0.2)

        let binaryPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let absoluteBinary = (binaryPath as NSString).isAbsolutePath ? binaryPath : "\(FileManager.default.currentDirectoryPath)/\(binaryPath)"
        let configPath = ConfigManager.shared.configURL.path

        let agentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let logPath = Logger.shared.logPath
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(absoluteBinary)</string>
                <string>run</string>
                <string>--daemon</string>
                <string>--config</string>
                <string>\(configPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            let uid = getuid()
            _ = ScriptRunner.runCommand("launchctl bootout gui/\(uid) \(plistURL.path) 2>/dev/null; launchctl bootstrap gui/\(uid) \(plistURL.path)")
            print("\(Color.green)✅ Background service started successfully!\(Color.reset)")
            print("   Plist:  \(plistURL.path)")
            print("   Config: \(configPath)")
            print("   Logs:   \(logPath)")
        } catch {
            print("❌ Failed to start service: \(error)")
        }
    }

    static func stop() {
        let uid = getuid()
        _ = ScriptRunner.runCommand("launchctl bootout gui/\(uid) \(plistURL.path) 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
        print("\(Color.yellow)🛑 Background service stopped.\(Color.reset)")
    }

    static func restart() {
        stop()
        Thread.sleep(forTimeInterval: 0.5)
        start()
    }

    static func isRunning() -> (running: Bool, pid: String?) {
        let (_, out) = ScriptRunner.runCommand("launchctl list | grep \(label)")
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let parts = trimmed.split(separator: "\t")
            let pid = (parts.first.map { String($0) } ?? "-")
            return (true, pid == "-" ? "active (waiting)" : "pid \(pid)")
        }
        return (false, nil)
    }
}

// MARK: - CLI Formatters & Helpers

func renderGauge(angle: Double, width: Int = 25) -> String {
    let clamped = max(0.0, min(180.0, angle))
    let progress = clamped / 180.0
    let filled = Int(round(Double(width) * progress))
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    return "[\(bar)]"
}

func pad(_ s: String, _ len: Int) -> String {
    if s.count >= len { return String(s.prefix(len)) }
    return s + String(repeating: " ", count: len - s.count)
}

func printHelp() {
    print("""
    \(Color.bold)MacBook Lid Automator (lid-automator)\(Color.reset)
    Automate scripts, notifications, and system actions based on MacBook lid angles.

    \(Color.bold)DEFAULT CONFIG LOCATION:\(Color.reset)
        ~/.lid-automation/config

    \(Color.bold)USAGE:\(Color.reset)
        lid-automator <command> [options]

    \(Color.bold)COMMANDS:\(Color.reset)
        \(Color.cyan)list, ls\(Color.reset)               List all configured automations and status
        \(Color.cyan)add\(Color.reset)                    Add a new automation (interactive or via flags)
        \(Color.cyan)remove, rm <id>\(Color.reset)        Remove an automation by index or name
        \(Color.cyan)enable <id>\(Color.reset)           Enable an automation
        \(Color.cyan)disable <id>\(Color.reset)          Disable an automation
        \(Color.cyan)test <id>\(Color.reset)             Test-run an automation (runs script & sends notification)

        \(Color.cyan)run\(Color.reset)                    Run live listener in foreground (move lid to test)
        \(Color.cyan)start\(Color.reset)                  Start background daemon (persists on login)
        \(Color.cyan)stop\(Color.reset)                   Stop background daemon
        \(Color.cyan)restart\(Color.reset)                Restart background daemon
        \(Color.cyan)status\(Color.reset)                 Show lid angle, daemon status, and active config

        \(Color.cyan)logs\(Color.reset)                   View recent execution logs
            -f, --follow          Live stream new logs
            -n <count>            Number of lines (default: 30)
            --clear               Clear log file

        \(Color.cyan)config\(Color.reset)                 Choose, view, or edit configuration
            --choose <path>       Set and remember active config file path
            --reset               Reset to default (~/.lid-automation/config)
            --path                Print active config file location
            --edit                Open config file in $EDITOR
            --cat                 Print config JSON to stdout

    \(Color.bold)OPTIONS FOR 'add':\(Color.reset)
        --name <str>          Name of the automation
        --angle <str>         Angle condition (e.g. '<40', '>100', '30-60')
        --script <str>        Script command (e.g. 'node script.js', 'builtin:volume 80')
        --notify [str]        Send macOS notification on trigger ('yes', 'no', or custom text)
        --no-notify           Disable notification
        --trigger <mode>      Trigger mode: 'enter' (default), 'exit', 'closing', 'opening', 'change'
        --time <str>          Time window (e.g. '9am-6pm', '09:00-18:00')
        --days <str>          Scheduled days (e.g. 'weekdays', 'mon,wed,fri')
        --cooldown <sec>      Cooldown in seconds between triggers (default: 5)
        --rearm <deg>         Hysteresis re-arm angle threshold
        --disabled            Add rule in disabled state
    """)
}

func cmdList() {
    let entries = ConfigManager.shared.loadEntries()
    if entries.isEmpty {
        print("No automations configured yet. Add one with: \(Color.cyan)lid-automator add\(Color.reset)")
        print("Config location: \(ConfigManager.shared.configURL.path)")
        return
    }

    print("\n\(Color.bold)Lid Automations (\(entries.count)):\(Color.reset)")
    print("\(Color.gray)Active Config: \(ConfigManager.shared.configURL.path)\(Color.reset)\n")
    print(pad("#", 4) + pad("NAME", 28) + pad("ANGLE", 11) + pad("TRIGGER", 9) + pad("NOTIFY", 8) + pad("ENABLED", 10) + pad("RULES", 24) + pad("SCRIPT", 28))
    print(String(repeating: "─", count: 122))

    for (i, entry) in entries.enumerated() {
        let num = "[\(i + 1)]"
        let status = entry.enabled ? "\(Color.green)✔ yes\(Color.reset)   " : "\(Color.red)✖ no\(Color.reset)    "
        let angleStr = entry.angle.displayString
        let triggerStr = entry.trigger?.description ?? "enter"
        let notifStr = (entry.notify?.isEnabled == true) ? "\(Color.magenta)🔔 yes\(Color.reset) " : "\(Color.gray)no\(Color.reset)   "
        let rulesStr = entry.rules?.summary ?? "-"
        let nameStr = (entry.name.count > 26) ? String(entry.name.prefix(23)) + "..." : entry.name
        let scriptStr = (entry.script.count > 26) ? String(entry.script.prefix(23)) + "..." : entry.script

        print(pad(num, 4) + pad(nameStr, 28) + pad(angleStr, 11) + pad(triggerStr, 9) + notifStr + status + pad(rulesStr, 24) + pad(scriptStr, 28))
    }
    print("")
}

func cmdAdd(args: [String]) {
    var name: String?
    var angleStr: String?
    var script: String?
    var notify: NotifySetting? = .enabled
    var trigger: TriggerMode? = .enter
    var timeStr: String?
    var daysStr: String?
    var cooldown: Double?
    var rearm: Double?
    var enabled: Bool = true

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--name":
            if i + 1 < args.count { name = args[i + 1]; i += 1 }
        case "--angle":
            if i + 1 < args.count { angleStr = args[i + 1]; i += 1 }
        case "--script":
            if i + 1 < args.count { script = args[i + 1]; i += 1 }
        case "--trigger":
            if i + 1 < args.count { trigger = TriggerMode.parse(args[i + 1]); i += 1 }
        case "--notify":
            if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                notify = .custom(args[i + 1])
                i += 1
            } else {
                notify = .enabled
            }
        case "--no-notify":
            notify = .disabled
        case "--time":
            if i + 1 < args.count { timeStr = args[i + 1]; i += 1 }
        case "--days":
            if i + 1 < args.count { daysStr = args[i + 1]; i += 1 }
        case "--cooldown":
            if i + 1 < args.count { cooldown = Double(args[i + 1]); i += 1 }
        case "--rearm":
            if i + 1 < args.count { rearm = Double(args[i + 1]); i += 1 }
        case "--disabled":
            enabled = false
        default:
            break
        }
        i += 1
    }

    if name == nil {
        print("\(Color.bold)? Automation Name:\(Color.reset) ", terminator: "")
        fflush(stdout)
        if let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            name = line.trimmingCharacters(in: .whitespaces)
        }
    }

    if angleStr == nil {
        print("\(Color.bold)? Angle condition (e.g. '<40', '>100', '30-60'):\(Color.reset) ", terminator: "")
        fflush(stdout)
        if let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            angleStr = line.trimmingCharacters(in: .whitespaces)
        }
    }

    if script == nil {
        print("\(Color.bold)? Script/Command (or 'builtin:volume 80', 'builtin:brightness 90'):\(Color.reset) ", terminator: "")
        fflush(stdout)
        if let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            script = line.trimmingCharacters(in: .whitespaces)
        }
    }

    guard let finalName = name, let finalAngleStr = angleStr, let finalScript = script else {
        print("❌ Error: Missing required fields.")
        exit(1)
    }

    guard let angleCond = AngleCondition.parse(finalAngleStr) else {
        print("❌ Error: Invalid angle specification '\(finalAngleStr)'.")
        exit(1)
    }

    var rules: FilterRules? = nil
    if timeStr != nil || daysStr != nil || cooldown != nil || rearm != nil {
        let daysList = daysStr?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        rules = FilterRules(time: timeStr, cooldown: cooldown ?? 5.0, rearm: rearm, days: daysList)
    }

    let entry = AutomationEntry(name: finalName, angle: angleCond, script: finalScript, enabled: enabled, notify: notify, trigger: trigger, rules: rules)
    ConfigManager.shared.addEntry(entry)
    print("\n\(Color.green)✔ Added automation '\(finalName)' to \(ConfigManager.shared.configURL.path)! \(Color.reset)")
    cmdList()
}

func cmdRemove(target: String) {
    guard let idx = ConfigManager.shared.findIndex(query: target) else {
        print("❌ Automation '\(target)' not found.")
        return
    }
    let entries = ConfigManager.shared.loadEntries()
    let name = entries[idx].name
    if ConfigManager.shared.removeEntry(at: idx) {
        print("\(Color.green)✔ Removed automation [\(idx + 1)] '\(name)'.\(Color.reset)")
    }
}

func cmdToggle(target: String, enabled: Bool) {
    guard let idx = ConfigManager.shared.findIndex(query: target) else {
        print("❌ Automation '\(target)' not found.")
        return
    }
    let entries = ConfigManager.shared.loadEntries()
    let name = entries[idx].name
    if ConfigManager.shared.toggleEntry(at: idx, enabled: enabled) {
        let word = enabled ? "\(Color.green)enabled" : "\(Color.yellow)disabled"
        print("✔ Automation [\(idx + 1)] '\(name)' is now \(word).\(Color.reset)")
    }
}

func cmdTest(target: String) {
    guard let idx = ConfigManager.shared.findIndex(query: target) else {
        print("❌ Automation '\(target)' not found.")
        return
    }
    let entry = ConfigManager.shared.loadEntries()[idx]
    print("🧪 Testing automation: '\(entry.name)'")
    print("   Angle target: \(entry.angle.displayString) (trigger: \(entry.trigger?.description ?? "enter"))")
    print("   Notification: \(entry.notify?.isEnabled == true ? "🔔 Enabled" : "Disabled")")
    print("   Executing:    \(entry.script)\n")

    if let notify = entry.notify, notify.isEnabled {
        let notifMsg: String
        switch notify {
        case .custom(let customMsg): notifMsg = customMsg
        default: notifMsg = "Manual test of '\(entry.name)' • Angle: 105.0°"
        }
        ScriptRunner.sendNotification(title: "Lid Automator Test", subtitle: entry.name, message: notifMsg)
        print("\(Color.magenta)🔔 Sent desktop notification banner: '\(notifMsg)'\(Color.reset)")
    }

    let start = Date()
    let (code, output) = ScriptRunner.executeAction(script: entry.script, entryName: entry.name, angle: 105.0, prevAngle: 90.0)
    let elapsed = Int(Date().timeIntervalSince(start) * 1000)

    if code == 0 {
        Logger.shared.log(level: "SUCCESS", message: "Manual test of '\(entry.name)' succeeded in \(elapsed)ms")
        print("\(Color.green)✔ Action executed in \(elapsed)ms (exit code: 0)\(Color.reset)")
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Output:\n\(output)")
        }
    } else {
        Logger.shared.log(level: "ERROR", message: "Manual test of '\(entry.name)' failed (exit: \(code)) | \(output)")
        print("\(Color.red)✖ Action failed with exit code \(code) in \(elapsed)ms\(Color.reset)")
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Error output:\n\(output)")
        }
    }
}

func cmdStatus() {
    print("\n\(Color.bold)Lid Automator Status:\(Color.reset)")
    print(String(repeating: "─", count: 42))

    guard let reader = LidSensorReader() else {
        print("❌ Lid Sensor: Disconnected / Not Available")
        return
    }

    if let angle = reader.readCurrentAngle() {
        print("▶ Lid Angle:      \(Color.cyan)\(Color.bold)\(String(format: "%.1f°", angle))\(Color.reset)  \(renderGauge(angle: angle))")
    }

    let (running, detail) = DaemonManager.isRunning()
    if running {
        print("▶ Background:     \(Color.green)● Running\(Color.reset) (\(detail ?? "active"))")
    } else {
        print("▶ Background:     \(Color.gray)○ Stopped\(Color.reset) (start with: \(Color.cyan)lid-automator start\(Color.reset))")
    }

    let entries = ConfigManager.shared.loadEntries()
    let active = entries.filter { $0.enabled }.count
    print("▶ Config Rules:   \(entries.count) total (\(active) enabled)")
    print("▶ Active Config:  \(ConfigManager.shared.configURL.path)")
    print("▶ Log File:       \(Logger.shared.logPath)\n")
}

func cmdRun(args: [String]) {
    let isDaemon = args.contains("--daemon")
    Logger.shared.echoToStdout = !isDaemon

    guard let reader = LidSensorReader() else {
        Logger.shared.log(level: "ERROR", message: "Failed to open Apple SPU Lid Angle Sensor")
        exit(1)
    }

    let entries = ConfigManager.shared.loadEntries()
    Logger.shared.log(level: "INFO", message: "Lid Automator engine started with \(entries.count) rule(s) from \(ConfigManager.shared.configURL.path)")

    var activeStates = entries.map { ActiveRuleState(entry: $0) }

    if let currentAngle = reader.readCurrentAngle() {
        if !isDaemon {
            print("✨ Lid Automator active! Current angle: \(String(format: "%.1f°", currentAngle))")
            print("   Watching \(entries.filter { $0.enabled }.count) enabled automation(s)... Press Ctrl+C to stop.\n")
        }
        for state in activeStates {
            state.isArmed = !state.entry.angle.matches(angle: currentAngle)
            let status = state.isArmed ? "ARMED" : "UNARMED (in trigger range)"
            Logger.shared.log(level: "INFO", message: "Rule '\(state.entry.name)': [\(status)] Target: \(state.entry.angle.displayString) (trigger: \(state.entry.trigger?.description ?? "enter"), notify: \(state.entry.notify?.isEnabled == true))")
        }
    }

    // Live config watcher: hot-reloads new config automatically without restart
    let watcher = ConfigFileWatcher()
    watcher.onReload = { newEntries in
        let curAngle = reader.readCurrentAngle()
        var updatedStates: [ActiveRuleState] = []

        for entry in newEntries {
            let state = ActiveRuleState(entry: entry)
            if let existing = activeStates.first(where: { $0.entry.name == entry.name }) {
                state.isArmed = existing.isArmed
                state.lastTriggered = existing.lastTriggered
            } else if let angle = curAngle {
                state.isArmed = !entry.angle.matches(angle: angle)
            } else {
                state.isArmed = true
            }
            updatedStates.append(state)
        }

        activeStates = updatedStates
        let enabledCount = activeStates.filter { $0.entry.enabled }.count
        Logger.shared.log(level: "INFO", message: "🔄 Config hot-reloaded! Now watching \(enabledCount) active rule(s) from \(ConfigManager.shared.configURL.path)")

        if !isDaemon {
            print("\n\(Color.green)🔄 Config updated on disk! Hot-reloaded \(enabledCount) active automation(s).\(Color.reset)")
        }
    }
    watcher.start()

    signal(SIGINT) { _ in
        print("\nExiting Lid Automator.")
        exit(0)
    }

    reader.onAngleChange = { angle, prevAngle in
        if !isDaemon {
            print(String(format: "\rAngle: %5.1f°  %@", angle, renderGauge(angle: angle, width: 20)), terminator: "")
            fflush(stdout)
        }

        for state in activeStates {
            state.evaluate(angle: angle, prevAngle: prevAngle)
        }
    }

    reader.startStreaming()
}

// MARK: - Main Entry Point

var cliArgs = Array(CommandLine.arguments.dropFirst())

// Custom config flag support
if let cfgIdx = cliArgs.firstIndex(of: "--config"), cfgIdx + 1 < cliArgs.count {
    let path = cliArgs[cfgIdx + 1]
    ConfigManager.shared = ConfigManager(customPath: path)
    cliArgs.remove(at: cfgIdx + 1)
    cliArgs.remove(at: cfgIdx)
} else if let cfgIdx = cliArgs.firstIndex(of: "-c"), cfgIdx + 1 < cliArgs.count {
    let path = cliArgs[cfgIdx + 1]
    ConfigManager.shared = ConfigManager(customPath: path)
    cliArgs.remove(at: cfgIdx + 1)
    cliArgs.remove(at: cfgIdx)
}

let command = cliArgs.first ?? "status"
let subArgs = Array(cliArgs.dropFirst())

switch command {
case "list", "ls":
    cmdList()

case "add":
    cmdAdd(args: subArgs)

case "remove", "rm", "delete":
    guard let target = subArgs.first else {
        print("Usage: lid-automator rm <id|name>")
        exit(1)
    }
    cmdRemove(target: target)

case "enable":
    guard let target = subArgs.first else {
        print("Usage: lid-automator enable <id|name>")
        exit(1)
    }
    cmdToggle(target: target, enabled: true)

case "disable":
    guard let target = subArgs.first else {
        print("Usage: lid-automator disable <id|name>")
        exit(1)
    }
    cmdToggle(target: target, enabled: false)

case "test":
    guard let target = subArgs.first else {
        print("Usage: lid-automator test <id|name>")
        exit(1)
    }
    cmdTest(target: target)

case "status":
    cmdStatus()

case "run":
    cmdRun(args: subArgs)

case "start":
    DaemonManager.start()

case "stop":
    DaemonManager.stop()

case "restart":
    DaemonManager.restart()

case "logs":
    let follow = subArgs.contains("-f") || subArgs.contains("--follow")
    let clear = subArgs.contains("--clear")
    var lines = 30
    if let nIdx = subArgs.firstIndex(of: "-n"), nIdx + 1 < subArgs.count {
        lines = Int(subArgs[nIdx + 1]) ?? 30
    }
    if clear {
        Logger.shared.clear()
    } else {
        Logger.shared.view(lines: lines, follow: follow)
    }

case "config":
    if subArgs.contains("--choose") || subArgs.contains("--use") || subArgs.contains("--set") {
        let flag = subArgs.contains("--choose") ? "--choose" : (subArgs.contains("--use") ? "--use" : "--set")
        if let idx = subArgs.firstIndex(of: flag), idx + 1 < subArgs.count {
            let targetPath = subArgs[idx + 1]
            ConfigManager.shared.setChosenConfigPath(targetPath)
            print("✅ Active config file set to: \(ConfigManager.shared.configURL.path)")
            let (running, _) = DaemonManager.isRunning()
            if running {
                print("🔄 Restarting background daemon with new config...")
                DaemonManager.restart()
            }
        } else {
            print("Usage: lid-automator config --choose <path>")
        }
    } else if subArgs.contains("--reset") {
        ConfigManager.shared.resetToDefaultConfigPath()
        print("✅ Config reset to default: \(ConfigManager.shared.configURL.path)")
    } else if subArgs.contains("--path") {
        print(ConfigManager.shared.configURL.path)
    } else if subArgs.contains("--cat") {
        if let data = try? Data(contentsOf: ConfigManager.shared.configURL),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        } else {
            print("No config file found at \(ConfigManager.shared.configURL.path)")
        }
    } else if subArgs.contains("--edit") {
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "nano"
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = [editor, ConfigManager.shared.configURL.path]
        try? p.run()
        p.waitUntilExit()
    } else {
        print("Active config file: \(ConfigManager.shared.configURL.path)")
        print("Default location:   \(ConfigManager.defaultConfigURL.path)")
        print("\nCommands:")
        print("  lid-automator config --choose <path>   Set active config file")
        print("  lid-automator config --reset           Reset back to default")
        print("  lid-automator config --cat             Print JSON content")
        print("  lid-automator config --edit            Edit in $EDITOR")
    }

case "-h", "--help", "help":
    printHelp()

default:
    print("Unknown command '\(command)'. Run 'lid-automator --help' for available commands.")
    exit(1)
}
