import SwiftUI
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import IOKit.pwr_mgt

// MARK: - Settings (written by the installers from setup.command; defaults = original setup)

enum Config {
    private static let d = UserDefaults.standard
    static var displayName: String { d.string(forKey: "displayName") ?? "" }
    static var serverLabel: String { d.string(forKey: "serverLabel") ?? "Server" }
    static var clientLabel: String { d.string(forKey: "clientLabel") ?? "Laptop" }
    static var serverInput: String { d.string(forKey: "serverInputName") ?? "HDMI 1" }
    static var clientInput: String { d.string(forKey: "clientInputName") ?? "HDMI 2" }
}

// MARK: - Targets ("mini" = the server's input, "macbook" = the laptops' input)

enum Target: String {
    case mini, macbook

    var title: String {
        self == .mini ? "\(Config.serverLabel)  (\(Config.serverInput))" : "\(Config.clientLabel)  (\(Config.clientInput))"
    }
    var shown: String { "Showing " + (self == .mini ? Config.serverLabel : Config.clientLabel) }
}

// MARK: - Model

final class SwitchModel: ObservableObject {
    static let shared = SwitchModel()

    /// Laptops (installed from the client package) switch through the server over SSH.
    let isClient = UserDefaults.standard.string(forKey: "role") == "client"

    @Published var status = "Ready"
    @Published var working = false
    @Published var current: Target?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var autoTakeover = UserDefaults.standard.object(forKey: "autoTakeover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoTakeover, forKey: "autoTakeover") }
    }
    @Published var autoRelease = UserDefaults.standard.object(forKey: "autoRelease") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoRelease, forKey: "autoRelease") }
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    @Published var updating = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var script: String { home.appendingPathComponent(".local/bin/monitor-switch").path }
    private var stateURL: URL { home.appendingPathComponent(".local/state/monitor-switch/current") }
    private var timer: Timer?

    private init() {
        run("status", quiet: true)   // read the real input once at launch
        // First launch: start automatically at login (can be turned off in the menu).
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            setLaunchAtLogin(true)
        }
        // Switches made over SSH (from a laptop) update the state file; pick them up.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    func refreshState() {
        guard !working,
              let raw = try? String(contentsOf: stateURL, encoding: .utf8),
              let t = Target(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              t != current else { return }
        current = t
        status = t.shown
    }

    /// Switches to the other HDMI input (what ⌃⌥⌘M does).
    func toggle() { run("toggle") }
    func switchTo(_ target: Target) { run(target.rawValue) }

    /// Laptop only: claim the monitor (HDMI 2). Retries while Wi-Fi comes back after wake.
    func takeOver(attempt: Int = 1) {
        guard isClient, autoTakeover else { return }
        if attempt == 1 { status = "Taking over the monitor …" }
        run(Target.macbook.rawValue, quiet: true) { [weak self] ok in
            guard !ok, attempt < 6 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self?.takeOver(attempt: attempt + 1) }
        }
    }

    /// Laptop only: give the monitor back to the server (cable unplugged / going to sleep).
    func release(completion: (() -> Void)? = nil) {
        guard isClient, autoRelease else { completion?(); return }
        status = "Giving the monitor back to the server …"
        // "release": the server answers at once and switches in the background (~1 s).
        run("release", quiet: true) { _ in completion?() }
    }

    private func run(_ arg: String, quiet: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !working else { completion?(false); return }
        working = true
        if !quiet { status = "Switching …" }
        let script = self.script
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: script)
            task.arguments = [arg]
            let out = Pipe(), err = Pipe()
            task.standardOutput = out
            task.standardError = err
            var result: String?, failure: String?
            do {
                try task.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    result = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    failure = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.working = false
                if let failure {
                    self.status = "Error: " + String(failure.prefix(120))
                    if !quiet { NSSound.beep() }
                } else if let t = result.flatMap(Target.init(rawValue:)) {
                    self.current = t
                    self.status = t.shown
                }
                completion?(failure == nil)
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Auto take-over (laptops): shared monitor plugged in, or laptop woken with shared monitor attached

final class AutoTakeover {
    static let shared = AutoTakeover()
    private var present = false
    private var goneAt = Date.distantPast
    private var wokeRecently = false
    private var pending: DispatchWorkItem?
    private var lastTakeover = Date.distantPast
    private var releaseItem: DispatchWorkItem?

    static func sharedConnected() -> Bool {
        let name = Config.displayName
        guard !name.isEmpty else { return false }
        return NSScreen.screens.contains { $0.localizedName.localizedCaseInsensitiveContains(name) }
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedule() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.wokeRecently = true; self?.schedule() }
        schedule()   // at login: if the Dell is already attached, claim it
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)   // let the display settle
    }

    private func evaluate() {
        let connected = Self.sharedConnected()
        defer { wokeRecently = false }
        guard connected else {
            if present { present = false; goneAt = Date(); scheduleRelease() }
            return
        }
        releaseItem?.cancel()
        // Ignore short blips (some monitors re-announce themselves while changing input).
        let freshlyPlugged = !present && Date().timeIntervalSince(goneAt) >= 5
        present = true
        if freshlyPlugged || wokeRecently {
            lastTakeover = Date()
            SwitchModel.shared.takeOver()
        }
    }

    /// Cable unplugged: give the monitor back to the server, but only if the shared monitor stays gone
    /// for 5 s, and not right after we claimed it (the monitor blinks while changing input).
    private func scheduleRelease() {
        // Right after a take-over the shared monitor may vanish for a moment while it changes input, so
        // don't decide yet: check again once 20 s have passed since the take-over (at least 5 s
        // from now). If the cable was really unplugged, the shared monitor is still gone then.
        let sinceTakeover = Date().timeIntervalSince(lastTakeover)
        let delay = max(5, 20 - sinceTakeover)
        releaseItem?.cancel()
        let item = DispatchWorkItem { if !Self.sharedConnected() { SwitchModel.shared.release() } }
        releaseItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - Going to sleep (laptops): give the monitor back first

final class PowerWatcher {
    static let shared = PowerWatcher()
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private static let canSystemSleep: UInt32 = 0xE000_0270   // kIOMessageCanSystemSleep
    private static let systemWillSleep: UInt32 = 0xE000_0280  // kIOMessageSystemWillSleep

    func start() {
        root = IORegisterForSystemPower(nil, &port, { _, _, type, arg in
            PowerWatcher.shared.handle(type, Int(bitPattern: arg))
        }, &notifier)
        guard root != 0, let port else { NSLog("MonitorSwitcher: IORegisterForSystemPower failed"); return }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
    }

    private func handle(_ type: UInt32, _ id: Int) {
        switch type {
        case Self.canSystemSleep:
            IOAllowPowerChange(root, id)
        case Self.systemWillSleep:
            // Only if the shared monitor is attached to THIS laptop; otherwise someone else may be using it.
            guard AutoTakeover.sharedConnected() else { IOAllowPowerChange(root, id); return }
            var done = false
            let root = self.root
            let allow = { if !done { done = true; IOAllowPowerChange(root, id) } }
            SwitchModel.shared.release { allow() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { allow() }   // never block sleep for long
        default:
            break
        }
    }
}

// MARK: - Laptop keys (server only): ~/.ssh/authorized_keys lines that may only switch the monitor

struct LaptopKey: Identifiable, Hashable {
    let id: String        // base64 key body
    let type: String      // ssh-ed25519, ...
    let comment: String   // e.g. monitorswitch-<laptop name>

    var title: String { comment.isEmpty ? "(no name)" : comment }
    var short: String { type + " …" + String(id.suffix(12)) }
}

final class KeyStore: ObservableObject {
    @Published var keys: [LaptopKey] = []
    @Published var message = ""
    @Published var remoteLogin: Bool?
    @Published var newKey = ""             // text field (view state lives here: no @State macro needed)
    @Published var toRemove: LaptopKey?   // key waiting for confirmation

    private let home: URL
    private var sshDir: URL { home.appendingPathComponent(".ssh") }
    private var authURL: URL { sshDir.appendingPathComponent("authorized_keys") }
    private var forcedCommand: String { home.appendingPathComponent(".local/bin/monitor-switch-ssh").path }
    // Only lines with our forced command are ours (dell-switch-ssh: installs before 2.0).
    private static let markers = ["monitor-switch-ssh", "dell-switch-ssh"]
    private func isOurs(_ line: String) -> Bool { Self.markers.contains { line.contains($0) } }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    private func readLines() -> [String] {
        let text = (try? String(contentsOf: authURL, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func writeLines(_ lines: [String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir.path)
        try (lines.joined(separator: "\n") + "\n").write(to: authURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
    }

    static func parse(_ line: String) -> LaptopKey? {
        let parts = line.split(separator: " ").map(String.init)
        guard let i = parts.firstIndex(where: { $0.hasPrefix("ssh-") || $0.hasPrefix("ecdsa-") }),
              i + 1 < parts.count else { return nil }
        let comment = parts.count > i + 2 ? parts[(i + 2)...].joined(separator: " ") : ""
        return LaptopKey(id: parts[i + 1], type: parts[i], comment: comment)
    }

    func reload() {
        keys = readLines().filter(isOurs).compactMap(Self.parse)
        checkRemoteLogin()
    }

    /// Adds a pasted public key, restricted to switching the monitor. Returns true on success.
    @discardableResult
    func add(_ raw: String) -> Bool {
        let key = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let parts = key.split(separator: " ").map(String.init)
        guard parts.count >= 2,
              ["ssh-ed25519", "ssh-rsa"].contains(parts[0]) || parts[0].hasPrefix("ecdsa-sha2-"),
              parts[1].count >= 60, Data(base64Encoded: parts[1]) != nil else {
            message = "That is not a valid public key. Paste the whole line, starting with “ssh-ed25519 AAAA…”."
            return false
        }
        var lines = readLines()
        if lines.contains(where: { $0.contains(parts[1]) && isOurs($0) }) {
            message = "This key has already been added."
            return false
        }
        if lines.contains(where: { $0.contains(parts[1]) }) {
            message = "This key is already in authorized_keys without restrictions – leaving it unchanged."
            return false
        }
        lines.append("command=\"\(forcedCommand)\",restrict \(parts.joined(separator: " "))")
        do { try writeLines(lines) } catch {
            message = "Could not save the key: \(error.localizedDescription)"; return false
        }
        message = "Added \(parts.count > 2 ? parts[2...].joined(separator: " ") : "key"). That laptop can switch now."
        reload()
        return true
    }

    func remove(_ key: LaptopKey) {
        let lines = readLines().filter { !($0.contains(key.id) && isOurs($0)) }
        do { try writeLines(lines); message = "Removed \(key.comment.isEmpty ? "key" : key.comment)." }
        catch { message = "Could not remove the key: \(error.localizedDescription)" }
        reload()
    }

    private func checkRemoteLogin() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            p.arguments = ["-z", "-G", "1", "127.0.0.1", "22"]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            let on = (try? p.run()).map { p.waitUntilExit(); return p.terminationStatus == 0 } ?? false
            DispatchQueue.main.async { self.remoteLogin = on }
        }
    }
}

struct KeysView: View {
    @StateObject private var store = KeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When a laptop is installed for the first time, it prints its public key and copies it to the "
                 + "clipboard. Paste it here. The key can only switch the monitor – nothing else on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle().fill(store.remoteLogin == true ? Color.green : Color.orange).frame(width: 8, height: 8)
                switch store.remoteLogin {
                case .some(true):  Text("Remote Login is on.")
                case .some(false): Text("Remote Login is off – turn it on in System Settings → General → Sharing.")
                case .none:        Text("Checking Remote Login …")
                }
            }.font(.callout)

            GroupBox("Laptops") {
                if store.keys.isEmpty {
                    Text("No laptops added yet.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.keys) { k in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.title)
                                    Text(k.short).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove") { store.toRemove = k }
                            }
                        }
                    }.padding(4)
                }
            }

            Text("Add a laptop key").font(.headline)
            TextEditor(text: $store.newKey)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Paste from Clipboard") { store.newKey = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button("Add") { if store.add(store.newKey) { store.newKey = "" } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !store.message.isEmpty {
                Text(store.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear { store.reload() }
        .confirmationDialog("Remove \(store.toRemove?.title ?? "this key")?",
                            isPresented: Binding(get: { store.toRemove != nil },
                                                 set: { if !$0 { store.toRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let k = store.toRemove { store.remove(k) }
                store.toRemove = nil
            }
        } message: {
            Text("That laptop will no longer be able to switch the monitor.")
        }
    }
}

final class KeysWindow {
    static let shared = KeysWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: KeysView()))
            w.title = "Laptop Keys"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Update from the server (laptops, only when asked)

enum Updater {
    private static var script: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/monitor-switch-update").path
    }

    /// Asks the server for a newer client package and installs it. Never runs on its own,
    /// so nothing waits when the laptop is away from the server's network.
    static func check() {
        let model = SwitchModel.shared
        guard !model.updating else { return }
        guard FileManager.default.isExecutableFile(atPath: script) else {
            model.status = "Updater not installed – install the client package once by hand."; return
        }
        model.updating = true
        model.status = "Checking for updates …"
        let script = self.script
        DispatchQueue.global(qos: .userInitiated).async {
            let (code, out, err) = run(script, ["--check"])
            DispatchQueue.main.async {
                if code == 3 {
                    model.updating = false
                    model.status = "Server not reachable – updates work on the server's network."
                } else if code != 0 {
                    model.updating = false
                    model.status = "Update: " + String(err.prefix(120))
                } else if out.hasPrefix("update") {
                    model.status = "Installing \(out.split(separator: " ").last.map(String.init) ?? "update") …"
                    detach(script)   // the installer restarts the app with the new version
                } else {
                    model.updating = false
                    model.status = "Up to date (\(model.version))."
                }
            }
        }
    }

    private static func run(_ path: String, _ args: [String]) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (1, "", error.localizedDescription) }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, o.trimmingCharacters(in: .whitespacesAndNewlines),
                e.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs the updater outside this process: the installer quits and relaunches the app.
    private static func detach(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "/usr/bin/nohup \"$0\" </dev/null >/dev/null 2>&1 &!", path]
        try? p.run()
    }
}

// MARK: - Global hotkey ⌃⌥⌘M (Carbon; no Accessibility permission needed)

final class HotKey {
    static let shared = HotKey()
    private var ref: EventHotKeyRef?

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { SwitchModel.shared.toggle() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x44534C57), id: 1)   // 'DSLW'
        let rc = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey | controlKey),
                                     id, GetApplicationEventTarget(), 0, &ref)
        if rc != noErr { NSLog("MonitorSwitcher: hotkey not registered (\(rc)), already used by another app?") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.shared.register()
        if SwitchModel.shared.isClient {
            AutoTakeover.shared.start()
            PowerWatcher.shared.start()
        }
    }
}

// MARK: - Menu bar UI

@main
struct MonitorSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SwitchModel.shared

    var body: some Scene {
        MenuBarExtra(Config.displayName.isEmpty ? "Monitor Switcher" : Config.displayName, systemImage: "display") {
            Button("Switch to the Other Computer") { model.toggle() }
                .keyboardShortcut("m", modifiers: [.control, .option, .command])
                .disabled(model.working)
            Divider()
            item(.mini)
            item(.macbook)
            Divider()
            Text(model.status)
            Divider()
            if !model.isClient {
                Button("Laptop Keys …") { KeysWindow.shared.show() }
            }
            if model.isClient {
                Toggle("Take Over When the Cable Is Plugged In", isOn: $model.autoTakeover)
                Toggle("Give Back When Unplugged or Asleep", isOn: $model.autoRelease)
                Button("Update from Server") { Updater.check() }
                    .disabled(model.updating)
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))
            Button("Quit Monitor Switcher") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
            Divider()
            Text("Monitor Switcher \(model.version)")
        }
    }

    private func item(_ t: Target) -> some View {
        Toggle(t.title, isOn: Binding(
            get: { model.current == t },
            set: { _ in model.switchTo(t) }))
            .disabled(model.working)
    }
}
