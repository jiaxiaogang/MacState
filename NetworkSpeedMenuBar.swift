import Foundation
import AppKit
import Darwin

class NetworkSpeedApp: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var lastUploaded: UInt64 = 0
    var lastDownloaded: UInt64 = 0
    var menu: NSMenu!

    override init() {
        super.init()
        menu = NSMenu()
        menu.delegate = self
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func start() {
        if let button = statusItem.button {
            button.title = "↑ 0B/s ↓ 0B/s"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

            // 直接设置菜单
            statusItem.menu = menu

            // 添加手势识别
            let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            rightClick.buttonMask = 0x2  // 右键
            button.addGestureRecognizer(rightClick)
        }

        updateSpeed()

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateSpeed()
        }

        RunLoop.main.run()
    }

    @objc func handleRightClick(_ gesture: NSClickGestureRecognizer) {
        print("检测到右键点击")
        statusItem.button?.performClick(nil)
    }

    func updateSpeed() {
        let (currentUploaded, currentDownloaded) = getNetworkBytes()

        let uploaded = currentUploaded > lastUploaded ? currentUploaded - lastUploaded : 0
        let downloaded = currentDownloaded > lastDownloaded ? currentDownloaded - lastDownloaded : 0

        lastUploaded = currentUploaded
        lastDownloaded = currentDownloaded

        let uploadStr = formatSpeed(uploaded)
        let downloadStr = formatSpeed(downloaded)

        let displayText = "↑\(uploadStr) ↓\(downloadStr)"

        if let button = statusItem.button {
            button.title = displayText
        }
    }

    @objc func quitApp() {
        print("退出程序")
        NSApplication.shared.terminate(nil)
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
            return String(format: "%.1fGB/s", gb)
        } else if mb >= 1 {
            return String(format: "%.1fMB/s", mb)
        } else if kb >= 1 {
            return String(format: "%.1fKB/s", kb)
        } else {
            return "0B/s"
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let networkApp = NetworkSpeedApp()
networkApp.start()
