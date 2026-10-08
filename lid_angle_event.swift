import Foundation
import IOKit

// Private IOKit C-function pointer definitions
typealias IOHIDEventSystemClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>
typealias IOHIDEventSystemClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
typealias IOHIDEventSystemClientRegisterEventCallback = @convention(c) (
    AnyObject,
    @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?
) -> Void

typealias IOHIDEventSystemClientScheduleWithRunLoop = @convention(c) (AnyObject, CFRunLoop, CFString) -> Void
typealias IOHIDEventGetFloatValue = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double

// Open IOKit framework dynamically
guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
    print("❌ Failed to open IOKit framework")
    exit(1)
}

// Bind C symbols
let clientCreate = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientCreate"), to: IOHIDEventSystemClientCreate.self)
let clientSetMatching = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientSetMatching"), to: IOHIDEventSystemClientSetMatching.self)
let clientRegisterCallback = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientRegisterEventCallback"), to: IOHIDEventSystemClientRegisterEventCallback.self)
let clientSchedule = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientScheduleWithRunLoop"), to: IOHIDEventSystemClientScheduleWithRunLoop.self)
let eventGetFloat = unsafeBitCast(dlsym(iokit, "IOHIDEventGetFloatValue"), to: IOHIDEventGetFloatValue.self)

// Create HID Event System Client
let client = clientCreate(kCFAllocatorDefault).takeRetainedValue()

// Match the Orientation HID Sensor Page
let matchingDict: [String: Any] = [
    "PrimaryUsagePage": 0x0020, // Sensor Page
    "PrimaryUsage": 0x008A      // Orientation / Lid Sensor
]
clientSetMatching(client, matchingDict as CFDictionary)

// Orientation field key offset inside IOKit events
let kIOHIDEventFieldOrientationAngle: UInt32 = (0x0020 << 16) | 0x01

// Callback function triggered when the hinge rotates
let callback: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?
) -> Void = { target, context, service, event in
    guard let event = event else { return }
    let rawGetFloat = unsafeBitCast(dlsym(dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW), "IOHIDEventGetFloatValue"), to: IOHIDEventGetFloatValue.self)
    
    let angle = rawGetFloat(event, kIOHIDEventFieldOrientationAngle)
    if angle > 0 {
        print(String(format: "Live Lid Angle: %.2f°", angle))
    }
}

// Register callback & attach to the main thread's RunLoop
clientRegisterCallback(client, callback, nil, nil)
clientSchedule(client, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

print("Listening for continuous lid angle updates... (Move your MacBook display)")
CFRunLoopRun()