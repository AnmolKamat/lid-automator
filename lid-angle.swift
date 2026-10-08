#!/usr/bin/env swift

import Foundation
import IOKit.hid

/// A self-contained utility to read the MacBook lid angle sensor ("las").
/// Extracted and expanded based on techniques from UnfoldMyMac (https://github.com/satyajiit/UnfoldMyMac).

final class LidSensorReader {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var onChangeHandler: ((Double) -> Void)?
    private var lastAngle: Double = -1.0

    init?() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        
        // Match Apple (0x05AC) Sensor Page (0x0020) Lid Sensor Usage (0x008A)
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
        
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else {
            return nil
        }

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
        if let device = device {
            IOHIDDeviceClose(device, 0)
        }
        IOHIDManagerClose(manager, 0)
        buffer.deallocate()
    }

    /// Performs a synchronous feature report read (one-shot).
    func readAngle() -> Double? {
        guard let device = device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let angle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
        return (0...180).contains(angle) ? angle : nil
    }

    /// Starts a real-time event stream via input report callback.
    func streamAngles(onChange: @escaping (Double) -> Void) {
        guard let device = device else { return }
        self.onChangeHandler = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, sender, type, reportId, report, length in
            guard let context = context, result == kIOReturnSuccess, length >= 3 else { return }
            let this = Unmanaged<LidSensorReader>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            let angle = Double(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
            guard (0...180).contains(angle) else { return }
            
            if abs(angle - this.lastAngle) >= 0.1 {
                this.lastAngle = angle
                this.onChangeHandler?(angle)
            }
        }, context)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
    }
}

// Visual ASCII gauge for terminal output
func renderGauge(angle: Double, width: Int = 30) -> String {
    let clamped = max(0.0, min(180.0, angle))
    let progress = clamped / 180.0
    let filled = Int(round(Double(width) * progress))
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    return "[\(bar)]"
}

// CLI argument handling
let args = CommandLine.arguments.dropFirst()
let jsonMode = args.contains("--json") || args.contains("-j")
let onceMode = args.contains("--once") || args.contains("-1")
let helpMode = args.contains("--help") || args.contains("-h")

if helpMode {
    print("""
    MacBook Lid Angle Reader (via Apple SPU / LAS HID)
    Based on UnfoldMyMac: https://github.com/satyajiit/UnfoldMyMac

    USAGE:
        swift lid-angle.swift [OPTIONS]

    OPTIONS:
        -1, --once      Read the lid angle once and exit immediately
        -j, --json      Output results in JSON format
        -h, --help      Show this help message
        (default)       Live stream updates as you move the MacBook lid
    """)
    exit(0)
}

guard let reader = LidSensorReader() else {
    if jsonMode {
        print("{\"error\": \"Lid angle sensor not found or accessible on this Mac.\"}")
    } else {
        print("❌ Could not connect to MacBook Lid Angle Sensor (LAS).")
        print("   Note: This sensor is present on Apple Silicon MacBooks (M-series).")
    }
    exit(1)
}

if onceMode {
    if let angle = reader.readAngle() {
        if jsonMode {
            print(String(format: "{\"angle\": %.1f, \"unit\": \"degrees\"}", angle))
        } else {
            print(String(format: "Lid Angle: %.1f°  %@", angle, renderGauge(angle: angle)))
        }
        exit(0)
    } else {
        if jsonMode {
            print("{\"error\": \"Failed to read lid angle report.\"}")
        } else {
            print("❌ Failed to read lid angle report.")
        }
        exit(1)
    }
} else {
    // Handle Ctrl+C gracefully
    signal(SIGINT) { _ in
        print("\nExiting.")
        exit(0)
    }

    if !jsonMode {
        print("✨ MacBook Lid Angle Sensor active! Move your laptop screen to test.")
        print("   Press Ctrl+C to stop.\n")
    }

    // Read initial angle
    if let initial = reader.readAngle() {
        if jsonMode {
            print(String(format: "{\"angle\": %.1f, \"timestamp\": %f}", initial, Date().timeIntervalSince1970))
        } else {
            print(String(format: "▶ Current Angle: %5.1f°  %@", initial, renderGauge(angle: initial)))
        }
    }

    reader.streamAngles { angle in
        if jsonMode {
            print(String(format: "{\"angle\": %.1f, \"timestamp\": %f}", angle, Date().timeIntervalSince1970))
        } else {
            print(String(format: "\r▶ Current Angle: %5.1f°  %@", angle, renderGauge(angle: angle)))
            fflush(stdout)
        }
    }
}
