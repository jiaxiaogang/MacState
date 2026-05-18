import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate {
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
    var networkUpdateTimer: Timer?
    var networkInitSeconds = 0
    var networkLastData: [(String, UInt64, UInt64)]?
    var networkLastUpdateTime: Date?

    func log(_ msg: String) {
        print(msg)
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
        guard networkItem != nil else { return }
        networkMenuActive = true
        networkInitSeconds = 0

        networkMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中... (0/2秒)", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        networkMenu.addItem(loadingItem)

        networkMenu.addItem(NSMenuItem.separator())
        let netQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        netQuitItem.target = self
        networkMenu.addItem(netQuitItem)

        DispatchQueue.main.async { [weak self] in
            self?.networkItem.menu = self?.networkMenu
        }

        networkUpdateTimer?.invalidate()
        networkUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNetworkMenuData()
        }
        updateNetworkMenuData()
    }

    func updateNetworkMenuData() {
        guard networkMenuActive else {
            networkUpdateTimer?.invalidate()
            networkUpdateTimer = nil
            return
        }

        networkInitSeconds += 1

        if networkInitSeconds <= 2 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.networkMenuActive else { return }
                if let item = self.networkMenu.items.first {
                    item.title = "加载中... (\(self.networkInitSeconds)/2秒)"
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let currentData = self.runNettopOnce() else { return }

            let now = Date()
            var processes: [(String, String, String)] = []

            if let lastData = self.networkLastData, let lastTime = self.networkLastUpdateTime {
                let interval = now.timeIntervalSince(lastTime)
                if interval > 0 {
                    for (name, currIn, currOut) in currentData {
                        if let (_, lastIn, lastOut) = lastData.first(where: { $0.0 == name }) {
                            let inBytes = currIn > lastIn ? UInt64(Double(currIn - lastIn) / interval) : 0
                            let outBytes = currOut > lastOut ? UInt64(Double(currOut - lastOut) / interval) : 0
                            let inStr = self.formatBytes(inBytes)
                            let outStr = self.formatBytes(outBytes)
                            if inBytes > 0 || outBytes > 0 {
                                processes.append((name, inStr, outStr))
                            }
                        }
                    }
                }
            }

            self.networkLastData = currentData
            self.networkLastUpdateTime = now

            let sorted = processes.sorted { a, b in
                let aTotal = self.parseBytesToNum(a.1) + self.parseBytesToNum(a.2)
                let bTotal = self.parseBytesToNum(b.1) + self.parseBytesToNum(b.2)
                return aTotal > bTotal
            }
            let topProcesses = Array(sorted.prefix(5))

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.networkMenuActive else { return }

                let (uploaded, downloaded) = self.getNetworkBytes()
                let uploadStr = self.formatSpeed(uploaded)
                let downloadStr = self.formatSpeed(downloaded)

                self.networkMenu.removeAllItems()

                let netItem = NSMenuItem(title: "↑\(uploadStr) ↓\(downloadStr)", action: nil, keyEquivalent: "")
                netItem.isEnabled = false
                self.networkMenu.addItem(netItem)

                self.networkMenu.addItem(NSMenuItem.separator())

                for (name, bytesIn, bytesOut) in topProcesses {
                    let item = NSMenuItem(title: "↑\(bytesOut) ↓\(bytesIn) \(name)", action: nil, keyEquivalent: "")
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
            }
        }
    }

    func runNettopOnce() -> [(String, UInt64, UInt64)]? {
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
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var results: [(String, UInt64, UInt64)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }

            let nameWithPid = components[0].trimmingCharacters(in: .whitespaces)
            guard let inBytes = UInt64(components[1].trimmingCharacters(in: .whitespaces)),
                  let outBytes = UInt64(components[2].trimmingCharacters(in: .whitespaces)) else { continue }

            // 去掉 .pid 后缀（最后一个 . 后面全是数字的部分）
            var name = nameWithPid
            if let lastDotRange = name.range(of: ".", options: .backwards) {
                let suffix = name[lastDotRange.upperBound...]
                if suffix.allSatisfy({ $0.isNumber }) {
                    name = String(name[..<lastDotRange.lowerBound])
                }
            }
            results.append((name, inBytes, outBytes))
        }

        return results
    }

    func parseBytesToNum(_ str: String) -> UInt64 {
        if str.hasSuffix("GB") {
            let num = str.replacingOccurrences(of: "GB", with: "")
            return UInt64((Double(num) ?? 0) * 1024 * 1024 * 1024)
        } else if str.hasSuffix("MB") {
            let num = str.replacingOccurrences(of: "MB", with: "")
            return UInt64((Double(num) ?? 0) * 1024 * 1024)
        } else if str.hasSuffix("KB") {
            let num = str.replacingOccurrences(of: "KB", with: "")
            return UInt64((Double(num) ?? 0) * 1024)
        } else if str.hasSuffix("B") {
            let num = str.replacingOccurrences(of: "B", with: "")
            return UInt64(Double(num) ?? 0)
        }
        return 0
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
            networkUpdateTimer?.invalidate()
            networkUpdateTimer = nil
            self.log("networkMenuActive = false")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.log("menuWillOpen: \(menu === cpuMenu ? "cpuMenu" : (menu === memoryMenu ? "memoryMenu" : (menu === networkMenu ? "networkMenu" : "other")))")
        if menu === cpuMenu {
            cpuMenuActive = true
            self.log("cpuMenuActive = true")
        } else if menu === memoryMenu {
            memoryMenuActive = true
            self.log("memoryMenuActive = true")
        } else if menu === networkMenu {
            networkMenuActive = true
            self.log("networkMenuActive = true")
        }
    }

    func loadCpuData() {
        self.log("loadCpuData 开始")

        cpuMenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        cpuMenu.addItem(loadingItem)

        cpuMenu.addItem(NSMenuItem.separator())
        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)

        self.log("准备启动异步任务")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.log("异步任务开始执行")
            let topProcesses = self?.getTopCpuProcesses() ?? []
            self?.log("异步获取 CPU 数据完成, 进程数: \(topProcesses.count)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { self?.log("self 为 nil"); return }
                self.log("主线程执行, cpuMenuActive=\(self.cpuMenuActive)")

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
        self.log("loadCpuData 结束")
    }

    func loadMemoryData() {
        self.log("开始加载 Memory 数据")

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
            self?.log("异步获取 Memory 数据完成, 进程数: \(topProcesses.count)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { self?.log("self 为 nil"); return }
                self.log("主线程执行, memoryMenuActive=\(self.memoryMenuActive)")

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

    var cpuDetailWindow: NSWindow?
    var cpuDetailTimer: Timer?
    var cpuProcesses: [(String, Double)] = []

    @objc func showCpuMenu(_ sender: AnyObject?) {
        self.log("第1步: showCpuMenu 被调用")
        guard cpuItem != nil else { return }
        cpuMenuActive = true

        cpuMenu.removeAllItems()

        let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        cpuMenu.addItem(loadingItem)

        cpuMenu.addItem(NSMenuItem.separator())

        let detailItem = NSMenuItem(title: "详情...", action: #selector(showCpuDetail), keyEquivalent: "")
        detailItem.target = self
        cpuMenu.addItem(detailItem)

        cpuMenu.addItem(NSMenuItem.separator())

        let cpuCloseItem = NSMenuItem(title: "关闭", action: #selector(closeCpuItem), keyEquivalent: "")
        cpuCloseItem.target = self
        cpuMenu.addItem(cpuCloseItem)

        let cpuQuitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        cpuQuitItem.target = self
        cpuMenu.addItem(cpuQuitItem)

        self.log("第2步: CPU菜单已构建，准备显示")
        DispatchQueue.main.async { [weak self] in
            self?.log("第3步: 调用 cpuItem.menu = cpuMenu")
            self?.cpuItem?.menu = self?.cpuMenu
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let topProcesses = self?.getTopCpuProcesses() ?? []

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.cpuMenu.removeAllItems()

                let detailItem = NSMenuItem(title: "详情...", action: #selector(self.showCpuDetail), keyEquivalent: "")
                detailItem.target = self
                self.cpuMenu.addItem(detailItem)

                self.cpuMenu.addItem(NSMenuItem.separator())

                for (name, cpu) in topProcesses {
                    let processName = (name as NSString).lastPathComponent
                    let item = NSMenuItem(title: "\(String(format: "%.1f", cpu))% \(processName)", action: nil, keyEquivalent: "")
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
            }
        }
    }

    @objc func showCpuDetail() {
        self.log("第4步: showCpuDetail 被调用")
        if cpuDetailWindow != nil {
            cpuDetailWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CPU 占用详情"
        window.center()

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]

        let cpuColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cpu"))
        cpuColumn.title = "CPU"
        cpuColumn.width = 60
        tableView.addTableColumn(cpuColumn)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "应用"
        nameColumn.width = 200
        tableView.addTableColumn(nameColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.tag = 100

        scrollView.documentView = tableView
        window.contentView?.addSubview(scrollView)

        self.log("第5步: 窗口创建完成，准备显示")
        cpuDetailWindow = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.log("第6步: 窗口已显示")

        self.log("第7步: 创建定时器，每秒刷新")
        cpuDetailTimer?.invalidate()
        cpuDetailTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCpuDetailTable()
        }
        updateCpuDetailTable()
    }

    func updateCpuDetailTable() {
        self.log("第8步: updateCpuDetailTable 被调用")
        // 直接在主线程执行 ps 命令
        let topProcesses = getTopCpuProcesses()
        self.cpuProcesses = topProcesses
        self.log("第9步: 获取到 \(topProcesses.count) 个进程")

        guard let window = self.cpuDetailWindow else {
            self.log("第10步失败: window 为 nil")
            return
        }
        if let scrollView = window.contentView?.subviews.first as? NSScrollView,
           let tableView = scrollView.documentView as? NSTableView {
            tableView.reloadData()
            self.log("第10步: 表格刷新完成")
        } else {
            self.log("第10步失败: 找不到 tableView")
        }
    }

    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return cpuProcesses.count
    }

    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < cpuProcesses.count else { return nil }
        let (name, cpu) = cpuProcesses[row]

        let cellId = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        var textField: NSTextField

        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField()
            textField.identifier = cellId
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
        }

        if tableColumn?.identifier.rawValue == "cpu" {
            textField.stringValue = String(format: "%.1f%%", cpu)
        } else {
            textField.stringValue = name
        }

        return textField
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 20
    }

    func closeCpuDetailWindow() {
        cpuDetailTimer?.invalidate()
        cpuDetailTimer = nil
        cpuDetailWindow?.close()
        cpuDetailWindow = nil
    }

    func getTopCpuProcesses() -> [(String, Double)] {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "/bin/ps -eo pid=,pcpu=,comm="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return []
        }

        var processes: [(String, Double)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            let components = line.split(whereSeparator: { $0.isWhitespace })
            guard components.count >= 3 else { continue }

            if let cpu = Double(components[1].description) {
                let name = String(components[2])
                if !name.isEmpty {
                    processes.append((name, cpu / Double(coreCount)))
                }
            }
        }

        return processes.sorted { $0.1 > $1.1 }.prefix(10).map { $0 }
    }

    @objc func showMemoryMenu(_ sender: AnyObject?) {
        self.log("showMemoryMenu 被调用")
        guard memoryItem != nil else { self.log("memoryItem 为 nil"); return }
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

        // 设置菜单（异步，跟 network 一样）
        DispatchQueue.main.async { [weak self] in
            self?.memoryItem?.menu = self?.memoryMenu
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.log("开始异步获取 Memory 数据")
            let topProcesses = self?.getTopMemoryProcesses() ?? []
            self?.log("获取到 \(topProcesses.count) 个进程")

            DispatchQueue.main.async { [weak self] in
                self?.log("主线程更新 Memory 菜单")
                guard let self = self else { return }

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
        task.arguments = ["-eo", "rss,comm"]

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
                let fullPath = components.last?.description ?? "Unknown"
                let name = (fullPath as NSString).lastPathComponent
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

    @objc func quitApp() {
        networkUpdateTimer?.invalidate()
        cpuDetailTimer?.invalidate()
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

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === cpuDetailWindow {
            closeCpuDetailWindow()
        }
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
