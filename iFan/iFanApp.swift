import SwiftUI
import AppKit

@main
enum EntryPoint {
    static func main() {
        FanController.runDaemonIfNeeded()
        iFanApp.main()
    }
}

struct iFanApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("iFan", id: "main") {
            MainWindowView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            MenuContentView(state: state)
        } label: {
            MenuBarLabelView(state: state)
        }
    }
}

private struct MenuContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Button("显示主窗口") { showMainWindow() }
        Divider()
        Text("预设选择")
        ForEach(state.policies) { policy in
            Button { state.applyPolicy(policy) } label: {
                if policy.id == state.currentPolicyID {
                    Text("✓ " + policy.name).bold()
                } else {
                    Text("  " + policy.name)
                }
            }
        }
        Divider()
        Button("退出 iFan") { NSApplication.shared.terminate(nil) }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "iFan" }) {
            w.makeKeyAndOrderFront(nil)
        } else if let opener = NSApp.delegate as? AppDelegate {
            opener.openMainWindow()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.first?.delegate = self
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] n in
            if let w = n.object as? NSWindow, w.title == "iFan" {
                self?.mainWindow = w; w.delegate = self
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.title == "iFan" || sender == mainWindow {
            sender.orderOut(nil); NSApp.setActivationPolicy(.accessory); return false
        }
        return true
    }
    func openMainWindow() { mainWindow?.makeKeyAndOrderFront(nil) }
}

// MARK: - Menu bar label (3s refresh via tick, data from @ObservedObject directly)

private struct MenuBarLabelView: View {
    @ObservedObject var state: AppState

    @State private var rotationAngle: Double = 0
    @State private var tick: Int = 0

    private var isManual: Bool { !state.currentPolicy.isSystem }

    private let animTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let dataTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let snap = state.snapshot
        _ = tick  // body depends on tick, so re-renders every 3s

        return HStack(spacing: 4) {
            Image(systemName: "fan.fill")
                .font(.system(size: 13))
                .rotationEffect(.degrees(rotationAngle))
                .animation(isManual ? .linear(duration: 1).repeatForever(autoreverses: false) : .easeOut(duration: 0.25), value: rotationAngle)

            VStack(alignment: .leading, spacing: -1) {
                fixedWidthText(Self.fmtTop(snap), reserve: "100.0", size: 8, color: tempColor(Self.fmtTop(snap)))
                fixedWidthText(Self.fmtBot(snap), reserve: "100.0", size: 8, color: tempColor(Self.fmtBot(snap)))
            }

            fixedWidthText(Self.fmtRPM(snap), reserve: "9.9k", size: 9, color: .secondary)
        }
        .onReceive(animTimer) { _ in
            if isManual {
                rotationAngle += 18
                if rotationAngle >= 360 { rotationAngle -= 360 }
            } else if rotationAngle != 0 { rotationAngle = 0 }
        }
        .onReceive(dataTimer) { _ in
            tick &+= 1
        }
    }

    static func fmtTop(_ snap: SensorSnapshot) -> String {
        if let cpu = snap.cpuTemp { return String(format: "%.1f", cpu) }
        if let gpu = snap.gpuTemp  { return String(format: "G%.0f", gpu) }
        return "--"
    }
    static func fmtBot(_ snap: SensorSnapshot) -> String {
        if let cpu = snap.cpuMaxTemp { return String(format: "%.1f", cpu) }
        if let gpu = snap.gpuMaxTemp { return String(format: "G%.0f", gpu) }
        return "--"
    }
    static func fmtRPM(_ snap: SensorSnapshot) -> String {
        guard let rpm = snap.avgRPM else { return "--" }
        return rpm >= 1000 ? String(format: "%.1fk", rpm / 1000) : String(format: "%.0f", rpm)
    }

    /// 用隐藏的最宽占位文本撑开固定宽度，保证数值变化时菜单栏图标不位移。
    private func fixedWidthText(_ value: String, reserve: String, size: CGFloat, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Text(reserve)
                .font(.system(size: size, design: .monospaced).monospacedDigit())
                .hidden()
            Text(value)
                .font(.system(size: size, design: .monospaced).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func tempColor(_ s: String) -> Color {
        let cleaned = s.replacingOccurrences(of: "G", with: "")
        guard let t = Double(cleaned) else { return .primary }
        switch t { case ..<55: return .green; case 55..<75: return .orange; default: return .red }
    }
}
