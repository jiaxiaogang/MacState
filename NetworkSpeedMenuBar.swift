import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lastUploaded: UInt64 = 0
    var lastDownloaded: UInt64 = 0
    var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            button.menu = menu
            button.title = "↑ 0B/s ↓ 0B/s"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

            let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            button.addGestureRecognizer(clickRecognizer)
        }

        updateSpeed()

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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

        let displayText = "↑\(uploadStr) ↓\(downloadStr)"

        if let button = statusItem.button {
            button.title = displayText
        }
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
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
