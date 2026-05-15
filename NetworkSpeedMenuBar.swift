import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var networkItem: NSStatusItem!
    var cpuItem: NSStatusItem!
    var memoryItem: NSStatusItem!
    var hdItem: NSStatusItem!
    var lastUploaded: UInt64 = 0
    var lastDownloaded: UInt64 = 0
    var lastCpuInfo: host_cpu_load_info?
    var networkMenu: NSMenu!
    var cpuMenu: NSMenu!
    var memoryMenu: NSMenu!
    var hdMenu: NSMenu!
    var cpuMenuActive = false
    var memoryMenuActive = false
    
    var networkMenuActive = false

    func log(_ msg: String) {
        let path = NSHomeDirectory() + "/Desktop/repos/MacState/log.txt"
        let date = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let str = "[\(fmt.string(from: date))] \(msg)\n"
        if let data = str.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func clearLog() {
        let path = NSHomeDirectory() + "/Desktop/repos/MacState/log.txt"
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearLog()
        self.log("应用启动")
        // 磁盘状态项
        hdItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hdMenu = NSMenu()
        let hdCloseItem = NSMenuItem(title: "关闭", action: #selector(closeHdItem), keyEquivalent: "")
        hdCloseItem.target = self
        hdMenu.addItem(hdCloseItem)
        let hdQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        hdQuitItem.target = self
        hdMenu.addItem(hdQuitItem)

        if let button = hdItem.button {
            button.title = "H0%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(showHdMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 内存状态项
        memoryItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        memoryMenu = NSMenu()
        memoryMenu.delegate = self
        let memCloseItem = NSMenuItem(title: "关闭", action: #selector(closeMemoryItem), keyEquivalent: "")
        memCloseItem.target = self
        memoryMenu.addItem(memCloseItem)
        let memQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        memQuitItem.target = self
        memoryMenu.addItem(memQuitItem)
        // memoryItem.menu = memoryMenu // 移除这行

        if let button = memoryItem.button {
            button.title = "M0%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.action = #selector(showMemoryMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // CPU 状态项
        cpuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        cpuMenu = NSMenu()
        cpuMenu.delegate = self
        let cpuCloseItem = NSMenuItem(title: "关闭", action: #selector(closeCpuItem), keyEquivalent: "")
        cpuCloseItem.target = self
        cpuMenu.addItem(cpuCloseItem)
        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)
        // cpuItem.menu = cpuMenu // 移除这行

        if let button = cpuItem.button {
            button.title = "C0%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.action = #selector(showCpuMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // 网络状态项
        networkItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        networkMenu = NSMenu()
        let netCloseItem = NSMenuItem(title: "关闭", action: #selector(closeNetworkItem), keyEquivalent: "")
        netCloseItem.target = self
        networkMenu.addItem(netCloseItem)
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

        lastCpuInfo = getCpuInfo()
        updateSpeed()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_) in
            self?.updateSpeed()
        }
    }

    @objc func showNetworkMenu(_ sender: AnyObject?) {
        self.log("showNetworkMenu 被调用")
        guard let networkItem = networkItem else { return }
        networkMenuActive = true
        self.log("networkMenuActive 设为 true")

        self.log("开始加载 Network 菜单")
        networkMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        networkMenu.addItem(loadingItem)

        networkMenu.addItem(NSMenuItem.separator())
        let netQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        netQuitItem.target = self
        networkMenu.addItem(netQuitItem)

        networkItem.menu = networkMenu

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.log("开始异步获取 Network 数据")
            let topProcesses = self?.getTopNetworkProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个进程")

            DispatchQueue.main.async { [weak self] in
                self?.log("主线程更新 Network 菜单, networkMenuActive=\(self?.networkMenuActive ?? false)")
                guard let self = self, self.networkMenuActive else { self?.log("networkMenuActive 为 false 或 self 为 nil"); return }

                let (uploaded, downloaded) = self.getNetworkBytes()
                let uploadStr = self.formatSpeed(uploaded)
                let downloadStr = self.formatSpeed(downloaded)

                self.log("网速: ↑\(uploadStr) ↓\(downloadStr)")
                self.networkMenu.removeAllItems()

                let netItem = NSMenuItem(title: "↑\(uploadStr) ↓\(downloadStr)", action: nil, keyEquivalent: "")
                netItem.isEnabled = false
                self.networkMenu.addItem(netItem)

                self.networkMenu.addItem(NSMenuItem.separator())

                for (name, bytesIn, bytesOut) in topProcesses {
                    let item = NSMenuItem(title: "↓\(bytesIn) ↑\(bytesOut) \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.networkMenu.addItem(item)
                }

                self.networkMenu.addItem(NSMenuItem.separator())

                let netCloseItem = NSMenuItem(title: "关闭", action: #selector(self.closeNetworkItem), keyEquivalent: "")
                netCloseItem.target = self
                self.networkMenu.addItem(netCloseItem)

                let netQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                netQuitItem.target = self
                self.networkMenu.addItem(netQuitItem)
                self.log("Network 菜单更新完成")
            }
        }
    }

    func getTopNetworkProcesses() -> [(String, String, String)] {
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        task.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out"]

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

        var processes: [(String, String, String)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }

            let name = components[0]
            guard let inBytes = UInt64(components[1].trimmingCharacters(in: .whitespaces)),
                  let outBytes = UInt64(components[2].trimmingCharacters(in: .whitespaces)) else { continue }

            if inBytes > 0 || outBytes > 0 {
                let inStr = formatBytes(inBytes)
                let outStr = formatBytes(outBytes)
                processes.append((name, inStr, outStr))
                if processes.count >= 5 { break }
            }
        }

        return processes
    }

    func menuDidClose(_ menu: NSMenu) {
        self.log("menuDidClose: \(menu === cpuMenu ? "cpuMenu" : (menu === memoryMenu ? "memoryMenu" : (menu === networkMenu ? "networkMenu" : "other")))")
        if menu === cpuMenu {
            cpuMenuActive = false
            self.log("cpuMenuActive = false")
        } else if menu === memoryMenu {
            memoryMenuActive = false
            self.log("memoryMenuActive = false")
        } else if menu === networkMenu {
            networkMenuActive = false
            self.log("networkMenuActive = false")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.log("menuWillOpen: \(menu === cpuMenu ? "cpuMenu" : (menu === memoryMenu ? "memoryMenu" : (menu === networkMenu ? "networkMenu" : "other")))")
        if menu === cpuMenu {
            cpuMenuActive = true
            self.log("cpuMenuActive = true")
            loadCpuData()
        } else if menu === memoryMenu {
            memoryMenuActive = true
            self.log("memoryMenuActive = true")
            loadMemoryData()
        } else if menu === networkMenu {
            networkMenuActive = true
            self.log("networkMenuActive = true")
        }
    }
    
    func loadCpuData() {
        self.log("开始加载 CPU 数据")
        for item in cpuMenu.items {
            if item.title == "加载中..." {
                return
            }
        }
        
        cpuMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        cpuMenu.addItem(loadingItem)
        
        cpuMenu.addItem(NSMenuItem.separator())
        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let topProcesses = self?.getTopCpuProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个 CPU 进程")

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.cpuMenuActive else { self?.log("cpuMenuActive 为 false"); return }
                
                self.cpuMenu.removeAllItems()

                for (name, cpu) in topProcesses {
                    let item = NSMenuItem(title: "\(String(format: "%.1f", cpu))% \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.cpuMenu.addItem(item)
                }

                self.cpuMenu.addItem(NSMenuItem.separator())

                let cpuCloseItem = NSMenuItem(title: "关闭", action: #selector(self.closeCpuItem), keyEquivalent: "")
                cpuCloseItem.target = self
                self.cpuMenu.addItem(cpuCloseItem)

                let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                cpuQuitItem.target = self
                self.cpuMenu.addItem(cpuQuitItem)
                self.log("CPU 菜单更新完成")
            }
        }
    }
    
    func loadMemoryData() {
        self.log("开始加载 Memory 数据")
        for item in memoryMenu.items {
            if item.title == "加载中..." {
                return
            }
        }
        
        memoryMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        memoryMenu.addItem(loadingItem)
        
        memoryMenu.addItem(NSMenuItem.separator())
        let memQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        memQuitItem.target = self
        memoryMenu.addItem(memQuitItem)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let topProcesses = self?.getTopMemoryProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个 Memory 进程")

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.memoryMenuActive else { self?.log("memoryMenuActive 为 false"); return }
                
                let (used, total, _) = self.getMemoryUsage()
                let usedStr = self.formatBytes(used)
                let totalStr = self.formatBytes(total)
                
                self.log("内存: \(usedStr) / \(totalStr)")
                self.memoryMenu.removeAllItems()

                let memItem = NSMenuItem(title: "已用: \(usedStr) / \(totalStr)", action: nil, keyEquivalent: "")
                memItem.isEnabled = false
                self.memoryMenu.addItem(memItem)

                self.memoryMenu.addItem(NSMenuItem.separator())

                for (name, mem) in topProcesses {
                    let item = NSMenuItem(title: "\(mem) \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.memoryMenu.addItem(item)
                }

                self.memoryMenu.addItem(NSMenuItem.separator())

                let memCloseItem = NSMenuItem(title: "关闭", action: #selector(self.closeMemoryItem), keyEquivalent: "")
                memCloseItem.target = self
                self.memoryMenu.addItem(memCloseItem)

                let memQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                memQuitItem.target = self
                self.memoryMenu.addItem(memQuitItem)
                self.log("Memory 菜单更新完成")
            }
        }
    }

    @objc func showCpuMenu(_ sender: AnyObject?) {
        self.log("showCpuMenu 被调用")
        guard let cpuItem = cpuItem else { self.log("cpuItem 为 nil"); return }
        cpuMenuActive = true
        self.log("cpuMenuActive 设为 true")
        
        self.log("开始加载 CPU 菜单")
        cpuMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        cpuMenu.addItem(loadingItem)
        
        cpuMenu.addItem(NSMenuItem.separator())
        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)
        
        cpuItem.menu = cpuMenu
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.log("开始异步获取 CPU 数据")
            let topProcesses = self?.getTopCpuProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个进程")

            DispatchQueue.main.async { [weak self] in
                self?.log("主线程更新 CPU 菜单, cpuMenuActive=\(self?.cpuMenuActive ?? false)")
                guard let self = self, self.cpuMenuActive else { self?.log("cpuMenuActive 为 false 或 self 为 nil"); return }
                self.cpuMenu.removeAllItems()
                self.log("移除旧菜单项，添加新项")

                for (name, cpu) in topProcesses {
                    let item = NSMenuItem(title: "\(String(format: "%.1f", cpu))% \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.cpuMenu.addItem(item)
                }

                self.cpuMenu.addItem(NSMenuItem.separator())

                let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                cpuQuitItem.target = self
                self.cpuMenu.addItem(cpuQuitItem)
                self.log("CPU 菜单更新完成")
            }
        }
    }

    func getTopCpuProcesses() -> [(String, Double)] {
        let coreCount = Double(ProcessInfo.processInfo.processorCount)
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-eo", "pcpu,comm", "-r"]

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

        for line in lines.dropFirst() {
            let components = line.split(whereSeparator: { $0.isWhitespace })
            guard components.count >= 2 else { continue }

            if let cpu = Double(components[0].description), cpu > 0 {
                let name = components.last?.description ?? "Unknown"
                let normalizedCpu = cpu / coreCount
                processes.append((name, normalizedCpu))
                if processes.count >= 5 { break }
            }
        }

        return processes
    }

    @objc func showMemoryMenu(_ sender: AnyObject?) {
        self.log("showMemoryMenu 被调用")
        guard let memoryItem = memoryItem else { self.log("memoryItem 为 nil"); return }
        memoryMenuActive = true
        self.log("memoryMenuActive 设为 true")
        
        self.log("开始加载 Memory 菜单")
        memoryMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        memoryMenu.addItem(loadingItem)
        
        memoryMenu.addItem(NSMenuItem.separator())
        let memQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        memQuitItem.target = self
        memoryMenu.addItem(memQuitItem)

        memoryItem.menu = memoryMenu

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.log("开始异步获取 Memory 数据")
            let topProcesses = self?.getTopMemoryProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个进程")

            DispatchQueue.main.async { [weak self] in
                self?.log("主线程更新 Memory 菜单, memoryMenuActive=\(self?.memoryMenuActive ?? false)")
                guard let self = self, self.memoryMenuActive else { self?.log("memoryMenuActive 为 false 或 self 为 nil"); return }
                
                let (used, total, _) = self.getMemoryUsage()
                let usedStr = self.formatBytes(used)
                let totalStr = self.formatBytes(total)
                
                self.log("内存信息: \(usedStr) / \(totalStr)")
                self.memoryMenu.removeAllItems()

                let memItem = NSMenuItem(title: "已用: \(usedStr) / \(totalStr)", action: nil, keyEquivalent: "")
                memItem.isEnabled = false
                self.memoryMenu.addItem(memItem)

                self.memoryMenu.addItem(NSMenuItem.separator())

                for (name, mem) in topProcesses {
                    let item = NSMenuItem(title: "\(mem) \(name)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    self.memoryMenu.addItem(item)
                }

                self.memoryMenu.addItem(NSMenuItem.separator())

                let memQuitItem = NSMenuItem(title: "退出", action: #selector(self.quitApp), keyEquivalent: "q")
                memQuitItem.target = self
                self.memoryMenu.addItem(memQuitItem)
                self.log("Memory 菜单更新完成")
            }
        }
    }

    func getTopMemoryProcesses() -> [(String, String)] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-eo", "rss,comm", "-m"]

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

        var processes: [(String, String)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let components = line.split(whereSeparator: { $0.isWhitespace })
            guard components.count >= 2 else { continue }

            if let rss = UInt64(components[0].description), rss > 0 {
                let name = components.last?.description ?? "Unknown"
                let memStr = formatBytes(rss * 1024)
                processes.append((name, memStr))
                if processes.count >= 5 { break }
            }
        }

        return processes
    }

    func getMemoryUsage() -> (used: UInt64, total: UInt64, percent: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let activeMemory = UInt64(stats.active_count) * pageSize
        let wiredMemory = UInt64(stats.wire_count) * pageSize
        let compressedMemory = UInt64(stats.compressor_page_count) * pageSize

        let usedMemory = activeMemory + wiredMemory + compressedMemory
        let percent = Double(usedMemory) / Double(totalMemory) * 100

        return (usedMemory, totalMemory, percent)
    }

    func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1024 / 1024 / 1024
        let mb = Double(bytes) / 1024 / 1024

        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        } else {
            return String(format: "%.0fMB", mb)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func closeNetworkItem() {
        NSStatusBar.system.removeStatusItem(networkItem)
        networkItem = nil
        checkAllClosed()
    }
    
    @objc func closeCpuItem() {
        NSStatusBar.system.removeStatusItem(cpuItem)
        cpuItem = nil
        checkAllClosed()
    }
    
    @objc func closeMemoryItem() {
        NSStatusBar.system.removeStatusItem(memoryItem)
        memoryItem = nil
        checkAllClosed()
    }

    @objc func closeHdItem() {
        NSStatusBar.system.removeStatusItem(hdItem)
        hdItem = nil
        checkAllClosed()
    }

    @objc func showHdMenu(_ sender: AnyObject?) {
        guard let hdItem = hdItem else { return }
        hdMenu.removeAllItems()

        let (used, total, _) = getDiskUsageDetail()
        let freeSpace = total - used
        let usedStr = formatBytes(used)
        let totalStr = formatBytes(total)
        let freeStr = formatBytes(freeSpace)

        let hdItemMenu = NSMenuItem(title: "已用: \(usedStr) / \(totalStr)\n剩余: \(freeStr)", action: nil, keyEquivalent: "")
        hdItemMenu.isEnabled = false
        hdMenu.addItem(hdItemMenu)

        hdMenu.addItem(NSMenuItem.separator())

        let hdCloseItem = NSMenuItem(title: "关闭", action: #selector(closeHdItem), keyEquivalent: "")
        hdCloseItem.target = self
        hdMenu.addItem(hdCloseItem)

        let hdQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        hdQuitItem.target = self
        hdMenu.addItem(hdQuitItem)

        hdItem.menu = hdMenu
        hdItem.button?.performClick(nil)
    }

    func getDiskUsage() -> Double {
        let (used, total, _) = getDiskUsageDetail()
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    func getDiskUsageDetail() -> (used: UInt64, total: UInt64, percent: Double) {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = attributes[.systemSize] as? UInt64,
               let freeSize = attributes[.systemFreeSize] as? UInt64 {
                let usedSize = totalSize - freeSize
                let percent = Double(usedSize) / Double(totalSize) * 100
                return (usedSize, totalSize, percent)
            }
        } catch {
            return (0, 0, 0)
        }
        return (0, 0, 0)
    }

    func getFreeDiskSpace() -> String {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = attributes[.systemFreeSize] as? UInt64 {
                return formatBytes(freeSize)
            }
        } catch {
            return "0GB"
        }
        return "0GB"
    }

    func checkAllClosed() {
        if networkItem == nil && cpuItem == nil && memoryItem == nil && hdItem == nil {
            NSApplication.shared.terminate(nil)
        }
    }
    
     func updateSpeed() {
        let (currentUploaded, currentDownloaded) = getNetworkBytes()
        if lastUploaded == 0 && lastDownloaded == 0 {
            lastUploaded = currentUploaded
            lastDownloaded = currentDownloaded
            return
        }
        let uploaded = currentUploaded > lastUploaded ? currentUploaded - lastUploaded : 0
        let downloaded = currentDownloaded > lastDownloaded ? currentDownloaded - lastDownloaded : 0
        lastUploaded = currentUploaded
        lastDownloaded = currentDownloaded
        let uploadStr = formatSpeed(uploaded)
        let downloadStr = formatSpeed(downloaded)

        if let button = networkItem?.button {
            button.title = "↑" + uploadStr + "↓" + downloadStr
        }

        let cpuUsage = getCpuUsage()
        if let button = cpuItem?.button {
            button.title = "C" + String(cpuUsage) + "%"
        }

        let (_, _, memPercent) = getMemoryUsage()
        if let button = memoryItem?.button {
            button.title = "M" + String(Int(memPercent)) + "%"
        }

        _ = getDiskUsage()
        let freeSpace = getFreeDiskSpace()
        if let button = hdItem?.button {
            button.title = "H" + freeSpace
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
