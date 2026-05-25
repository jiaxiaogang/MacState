import Foundation
import IOKit

private let kSMCUserClientOpen: UInt32 = 0

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: UInt32 = 0
    var pSize: UInt32 = 0
    var dataType: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var result: UInt32 = 0
    var status: UInt32 = 0
    var data8: UInt32 = 0
    var data32: UInt32 = 0
}

private func fourCC(_ s: String) -> UInt32 {
    let c = Array(s.utf8)
    var r: UInt32 = 0
    for i in 0..<4 { r = r << 8; if i < c.count { r |= UInt32(c[i]) } }
    return r
}

private var smcDebug = true

private func smcRead(conn: io_connect_t, key: String) -> (dataType: UInt32, dataSize: UInt32, b0: UInt8, b1: UInt8)? {
    let keyCode = fourCC(key)
    let size = MemoryLayout<SMCKeyData>.stride

    // Step 1: Get key info
    var input = SMCKeyData()
    var output = SMCKeyData()
    input.key = keyCode
    input.data8 = 9
    var outSize = size
    let kr1 = withUnsafeMutablePointer(to: &input) { inp in
        withUnsafeMutablePointer(to: &output) { out in
            IOConnectCallStructMethod(conn, 2, inp, size, out, &outSize)
        }
    }
    guard kr1 == 0 else {
        if smcDebug { print("debug: smcRead(\(key)) keyinfo failed kr1=\(kr1) euid=\(geteuid())"); smcDebug = false }
        return nil
    }
    let dataType = output.dataType
    let dataSize = output.pSize

    // Step 2: Read bytes
    input = SMCKeyData()
    output = SMCKeyData()
    input.key = keyCode
    input.data8 = 5
    outSize = size
    let kr2 = withUnsafeMutablePointer(to: &input) { inp in
        withUnsafeMutablePointer(to: &output) { out in
            IOConnectCallStructMethod(conn, 2, inp, size, out, &outSize)
        }
    }
    guard kr2 == 0 else {
        if smcDebug { print("debug: smcRead(\(key)) read failed kr2=\(kr2)"); smcDebug = false }
        return nil
    }
    return (dataType, dataSize, output.bytes.0, output.bytes.1)
}

private func readTemp(conn: io_connect_t) -> Double? {
    for key in ["TC0P", "TC0D", "TC0E", "TC0F", "TC0C"] {
        if let r = smcRead(conn: conn, key: key), r.dataType == fourCC("SP78"), r.dataSize == 2 {
            let t = Double(r.b0) + Double(r.b1) / 256.0
            if t > 0, t < 130 { return t }
        }
    }
    return nil
}

private func readFan(conn: io_connect_t) -> Int? {
    // Read F0Ac (fan 0 actual speed)
    if let r = smcRead(conn: conn, key: "F0Ac") {
        let speed = (UInt32(r.b0) << 8) | UInt32(r.b1)
        if speed > 0 { return Int(speed) }
    }
    // Read F1Ac (fan 1)
    if let r = smcRead(conn: conn, key: "F1Ac") {
        let speed = (UInt32(r.b0) << 8) | UInt32(r.b1)
        if speed > 0 { return Int(speed) }
    }
    return nil
}

// Main
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0 else {
    // Try AppleSMC on newer macOS
    let service2 = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service2 != 0 else { print("error: no AppleSMC uid=\(getuid()) euid=\(geteuid())"); exit(1) }
    _ = service2
    exit(1)
}
var conn: io_connect_t = 0
let kr = IOServiceOpen(service, mach_task_self_, kSMCUserClientOpen, &conn)
IOObjectRelease(service)
guard kr == 0 else { print("error: open failed kr=\(kr) uid=\(getuid()) euid=\(geteuid())"); exit(1) }
defer { IOServiceClose(conn) }

let args = CommandLine.arguments.dropFirst()
if args.isEmpty || args.contains("temp") {
    if let t = readTemp(conn: conn) {
        print(String(format: "temp:%.1f", t))
    }
}
if args.isEmpty || args.contains("fan") {
    if let f = readFan(conn: conn) {
        print("fan:\(f)")
    }
}
