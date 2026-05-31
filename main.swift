import AppKit

// Menu-bar control panel for macOS AC-power timers: "display off after" and
// "computer sleep after". Reads current values from `pmset -g custom` (no root)
// and writes changes via `pmset -c` behind the native administrator-auth prompt
// (no sudoers edits, no stored password). "Sleep: Never" == keep-awake.
struct PowerState {
    var displaySleep: Int  // minutes, 0 = never
    var systemSleep: Int   // minutes, 0 = never
}

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let displayOptions = [1, 2, 5, 10, 15, 30, 0]   // 0 = Never, listed last
    private let sleepOptions = [30, 60, 90, 120, 180, 0]    // 0 = Never, listed last

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.image = NSImage(
            systemSymbolName: "bolt.circle", accessibilityDescription: "Power")
        menu.delegate = self
        statusItem.menu = menu
    }

    private func minutesLabel(_ m: Int) -> String { m == 0 ? "Không bao giờ" : "\(m) phút" }

    // Repopulate from live state every time the menu opens, so checkmarks and the
    // summary always reflect the current pmset/launchctl values (no stale display).
    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = readState()
        menu.removeAllItems()

        let display = NSMenuItem(title: "Tắt màn hình sau", action: nil, keyEquivalent: "")
        display.submenu = optionsMenu(displayOptions, current: state.displaySleep,
                                      action: #selector(setDisplaySleep(_:)))
        menu.addItem(display)

        let sleep = NSMenuItem(title: "Máy ngủ sau", action: nil, keyEquivalent: "")
        sleep.submenu = optionsMenu(sleepOptions, current: state.systemSleep,
                                    action: #selector(setSystemSleep(_:)))
        menu.addItem(sleep)

        let summary = NSMenuItem(
            title: "Hiện tại (sạc): màn \(minutesLabel(state.displaySleep)) · ngủ \(minutesLabel(state.systemSleep))",
            action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Khởi động cùng đăng nhập",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = isLoginEnabled() ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func optionsMenu(_ options: [Int], current: Int, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for value in options {
            let item = NSMenuItem(title: minutesLabel(value), action: action, keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = (value == current) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // Parse the AC-power block of `pmset -g custom`.
    private func readState() -> PowerState {
        let output = run("/usr/bin/pmset", ["-g", "custom"]) ?? ""
        var ac = output
        if let range = output.range(of: "AC Power:") {
            ac = String(output[range.upperBound...])
        }
        func value(of key: String) -> Int {
            for line in ac.split(separator: "\n") {
                let parts = line.split(separator: " ").filter { !$0.isEmpty }
                if parts.count >= 2, parts[0] == Substring(key), let v = Int(parts[1]) {
                    return v
                }
            }
            return -1
        }
        return PowerState(displaySleep: value(of: "displaysleep"), systemSleep: value(of: "sleep"))
    }

    @discardableResult
    private func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // Apply a pmset change on AC power, prompting for admin auth natively. The menu
    // closes on selection and repopulates via menuNeedsUpdate on the next open.
    private func applyPmset(key: String, minutes: Int) {
        let command = "/usr/bin/pmset -c \(key) \(minutes)"
        let source = "do shell script \"\(command)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("PowerMenu: pmset failed: \(error)") }
    }

    // --- Launch at login, via the app's LaunchAgent enable/disable override.
    // No root and no bootout, so toggling never kills the running instance.
    private let loginLabel = "com.minhnhat.powermenu"

    private func isLoginEnabled() -> Bool {
        let output = run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]) ?? ""
        for line in output.split(separator: "\n") where line.contains(loginLabel) {
            return !(line.contains("true") || line.contains("disabled"))
        }
        return true  // absent from the disabled list means enabled
    }

    private func setLogin(_ enabled: Bool) {
        let target = "gui/\(getuid())/\(loginLabel)"
        run("/bin/launchctl", [enabled ? "enable" : "disable", target])
    }

    @objc private func toggleLogin() { setLogin(!isLoginEnabled()) }

    @objc private func setDisplaySleep(_ sender: NSMenuItem) {
        applyPmset(key: "displaysleep", minutes: sender.tag)
    }

    @objc private func setSystemSleep(_ sender: NSMenuItem) {
        applyPmset(key: "sleep", minutes: sender.tag)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let controller = Controller()
application.delegate = controller
application.run()
