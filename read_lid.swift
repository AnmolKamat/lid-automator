import Foundation
import IOKit

// Function signatures for private IOKit Event APIs
typealias IOHIDEventSystemClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>
typealias IOHIDEventSystemClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
typealias IOHIDEventSystemClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
typealias IOHIDServiceClientCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
    print("❌ Failed to load IOKit framework")
    exit(1)
}

let clientCreate = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientCreate"), to: IOHIDEventSystemClientCreate.self)
let clientSetMatching = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientSetMatching"), to: IOHIDEventSystemClientSetMatching.self)
let copyServices = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientCopyServices"), to: IOHIDEventSystemClientCopyServices.self)
let copyProperty = unsafeBitCast(dlsym(iokit, "IOHIDServiceClientCopyProperty"), to: IOHIDServiceClientCopyProperty.self)

let client = clientCreate(kCFAllocatorDefault).takeRetainedValue()

let matchingDict: [String: Any] = [
    "PrimaryUsagePage": 0x0020,
    "PrimaryUsage": 0x008A
]
clientSetMatching(client, matchingDict as CFDictionary)

print("🔍 Polling Lid Sensor Stream (Press Ctrl+C to stop)...")

var lastAngle: Double = -1.0

while true {
    if let servicesUnmanaged = copyServices(client),
       let services = servicesUnmanaged.takeRetainedValue() as? [AnyObject] {
        
        for service in services {
            // Read orientation property from active service
            if let prop = copyProperty(service, "Orientation" as CFString)?.takeRetainedValue() {
                if let angleNum = prop as? NSNumber {
                    let angle = angleNum.doubleValue
                    if angle != lastAngle {
                        print(String(format: "Live Lid Angle: %.2f°", angle))
                        lastAngle = angle
                    }
                }
            }
        }
    }
    Thread.sleep(forTimeInterval: 0.05) // 20Hz refresh rate
}