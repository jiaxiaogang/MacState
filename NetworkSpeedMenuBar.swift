import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    var networkItem: NSStatusItem!
    var cpuItem: NSStatusItem!
    var lastUploaded: UInt64 = 0
    var lastDownloaded: UInt64 = 0
    var lastCpuInfo: host_cpu_load_info?
    var networkMenu: NSMenu!
    var cpuMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 网络状态项
        networkItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        networkMenu = NSMenu()
        let netQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        netQuitItem.target = self
        networkMenu.addItem(netQuitItem)

        if let button = networkItem.button {
            button.title = "↑0B↓0B"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(showNetworkMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // CPU 状态项
        cpuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        cpuMenu = NSMenu()
        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)

        if let button = cpuItem.button {
            button.title = "CPU0%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(showCpuMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        lastCpuInfo = getCpuInfo()
        updateSpeed()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_) in
            self?.updateSpeed()
        }
    }

    @objc func showNetworkMenu(_ sender: AnyObject?) {
        networkItem.menu = networkMenu
        networkItem.button?.performClick(nil)
    }

    @objc func showCpuMenu(_ sender: AnyObject?) {
        cpuMenu.removeAllItems()

        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        cpuMenu.addItem(loadingItem)

        cpuMenu.addItem(NSMenuItem.separator())

        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)

        cpuItem.menu = cpuMenu
        cpuItem.button?.performClick(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let topProcesses = self?.getTopCpuProcesses() ?? []

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.cpuMenu.removeAllItems()

                for (name, cpu) in topProcesses {
                    let item = NSMenuItem(title: "\(String(format: "%.1f", cpu))% \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.cpuMenu.addItem(item)
                }

                self.cpuMenu.addItem(NSMenuItem.separator())

                let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                cpuQuitItem.target = self
                self.cpuMenu.addItem(cpuQuitItem)
            }
        }
    }

    func getTopCpuProcesses() -> [(String, Double)] {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "top -l 1 -n 5 -o cpu | head -20"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var processes: [(String, Double)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let components = line.split(whereSeparator: { $0.isWhitespace })
            guard components.count >= 2 else { continue }

            if let cpu = Double(components[0].description), cpu > 0 && cpu < 100 {
                let name = components.count > 5 ? components[5].description : components.last?.description ?? "Unknown"
                processes.append((name, cpu))
                if processes.count >= 5 { break }
            }
        }

        return processes
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

        if let button = networkItem.button {
            button.title = "↑" + uploadStr + "↓" + downloadStr
        }

        let cpuUsage = getCpuUsage()
        if let button = cpuItem.button {
            button.title = "CPU" + String(cpuUsage) + "%"
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
