import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lastUploaded: UInt64 = 0
    var lastDownloaded: UInt64 = 0
    var lastCpuInfo: host_cpu_load_info?
    var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.menu = menu
            button.title = "Net: 0B/s CPU: 0%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

            let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            button.addGestureRecognizer(clickRecognizer)
        }

        lastCpuInfo = getCpuInfo()
        updateSpeed()

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] (_) in
            self?.updateSpeed()
        }
    }

    @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
        if let button = statusItem.button {
            statusItem.menu = menu
            button.performClick(nil)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func updateSpeed() {
        let (currentUploaded, currentDownloaded) = getNetworkBytes()

        let uploaded = currentUploaded > lastUploaded ? currentUploaded - lastUploaded : 0
        let downloaded = currentDownloaded > lastDownloaded ? currentDownloaded - lastDownloaded : 0

        lastUploaded = currentUploaded
        lastDownloaded = currentDownloaded

        let uploadStr = formatSpeed(uploaded)
        let downloadStr = formatSpeed(downloaded)
        let cpuUsage = getCpuUsage()

        let displayText = "Net: \(uploadStr)/\(downloadStr) CPU: \(cpuUsage)%"

        if let button = statusItem.button {
            button.title = displayText
        }
    }

    func getCpuInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var cpuInfo = host_cpu_load_info()
        let hostInfo = withUnsafeMutablePointer(to: &cpuInfo) { $0 }
        let result = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
        }
        guard result == KERN_SUCCESS else { return nil }
        return cpuInfo
    }

    func getCpuUsage() -> Int {
        guard let currentCpu = getCpuInfo(), let previousCpu = lastCpuInfo else {
            lastCpuInfo = getCpuInfo()
            return 0
        }

        let userDiff = Int(currentCpu.cpu_ticks.0) - Int(previousCpu.cpu_ticks.0)
        let systemDiff = Int(currentCpu.cpu_ticks.1) - Int(previousCpu.cpu_ticks.1)
        let idleDiff = Int(currentCpu.cpu_ticks.2) - Int(previousCpu.cpu_ticks.2)
        let niceDiff = Int(currentCpu.cpu_ticks.3) - Int(previousCpu.cpu_ticks.3)

        let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
        guard totalDiff > 0 else {
            lastCpuInfo = currentCpu
            return 0
        }

        let used = userDiff + systemDiff + niceDiff
        let usage = Double(used) / Double(totalDiff) * 100

        lastCpuInfo = currentCpu
        return Int(usage)
    }

    func getNetworkBytes() -> (uploaded: UInt64, downloaded: UInt64) {
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrs) == 0, let firstAddr = ifaddrs else {
            return (0, 0)
        }

        defer { freeifaddrs(ifaddrs) }

        var totalUploaded: UInt64 = 0
        var totalDownloaded: UInt64 = 0

        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)

            if name != "lo0" && (ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK)) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalUploaded += UInt64(networkData.ifi_obytes)
                    totalDownloaded += UInt64(networkData.ifi_ibytes)
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return (totalUploaded, totalDownloaded)
    }

    func formatSpeed(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        } else if mb >= 1 {
            return String(format: "%.1fMB", mb)
        } else if kb >= 1 {
            return String(format: "%.0fKB", kb)
        } else {
            return "0B"
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
