#if canImport(DashboardCore)
import DashboardCore
#endif
import AppKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
struct DashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("KapiBoard", systemImage: "rectangle.grid.2x2") {
            KapiBoardMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var refreshTask: Task<Void, Never>?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = DashboardViewModel()
        refreshTask = Task {
            await viewModel.startRefreshLoop()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard KapiBoardURLHandler.handle(url) else {
                continue
            }
            if url.host != "arxiv" {
                application.hide(nil)
            }
        }
    }
}

enum DashboardFocusTarget {
    case arxiv
}

struct DashboardFocusRequest: Equatable {
    var id = UUID()
    var target: DashboardFocusTarget
}

@MainActor
final class DashboardNavigationStore: ObservableObject {
    static let shared = DashboardNavigationStore()

    @Published var focusRequest: DashboardFocusRequest?

    func focus(_ target: DashboardFocusTarget) {
        focusRequest = DashboardFocusRequest(target: target)
    }
}

@MainActor
enum KapiBoardURLHandler {
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme == "kapiboard" else {
            return false
        }

        if url.host == "refresh" {
            let arxivDigest = ArxivDigestStore.load()
            if arxivDigest.status == "ready" {
                try? ArxivDigestStore.save(arxivDigest)
            }
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
#endif
            return true
        }

        if url.host == "arxiv" {
            DashboardWindowController.shared.show(focus: .arxiv)
            return true
        }

        guard url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let source = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let sourceURL = URL(string: source),
              let scheme = sourceURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return false
        }

        NSWorkspace.shared.open(sourceURL)
        return true
    }
}

@MainActor
private final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    func show(focus target: DashboardFocusTarget? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let target {
            DashboardNavigationStore.shared.focus(target)
        }
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: DashboardRootView(navigation: DashboardNavigationStore.shared)
                .frame(minWidth: 980, minHeight: 680)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "KapiBoard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        return window
    }
}

private struct KapiBoardMenu: View {
    var body: some View {
        Button("Open Dashboard") {
            DashboardWindowController.shared.show()
        }

        Divider()

        Button("Quit KapiBoard") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
