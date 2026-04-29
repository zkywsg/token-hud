// token_hud/App/AppDelegate.swift
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Defaults {
        static let didOpenSettingsOnFirstLaunch = "didOpenSettingsOnFirstLaunch"
    }

    private var stateWatcher: StateWatcher!
    private var widgetStore: WidgetStore!
    private var appFilterStore: AppFilterStore!
    private var appWatcher: AppWatcher!
    private var floatingPanelManager: FloatingPanelManager!
    private var hotkeyManager: GlobalHotkeyManager!
    private var statusItem: NSStatusItem?
    private var settingsController: NSWindowController?
    private var codexFetcher: CodexFetcher!
    private var apiPlatformFetcher: APIPlatformFetcher!
    private var didFinishInitialLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = Self.makeAppIcon()

        stateWatcher    = StateWatcher()
        widgetStore     = WidgetStore()
        appFilterStore  = AppFilterStore()
        appWatcher      = AppWatcher()
        stateWatcher.start()
        appWatcher.start()
        codexFetcher = CodexFetcher()
        apiPlatformFetcher = APIPlatformFetcher()

        floatingPanelManager = FloatingPanelManager(
            stateWatcher: stateWatcher,
            widgetStore: widgetStore
        )
        floatingPanelManager.setup()

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager.onHotkey = { [weak self] in
            self?.floatingPanelManager.toggle()
        }
        hotkeyManager.setup()

        if !GlobalHotkeyManager.isAccessibilityEnabled {
            GlobalHotkeyManager.requestAccessibility()
        }

        setupStatusBar()
        didFinishInitialLaunch = true

        openSettingsOnFirstLaunchIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, didFinishInitialLaunch { openSettings() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateWatcher.stop()
        appWatcher.stop()
        floatingPanelManager.teardown()
        hotkeyManager.teardown()
        codexFetcher.stop()
        apiPlatformFetcher.stop()
    }

    // MARK: - App Icon

    private static func makeAppIcon() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Background: rounded rect with gradient
        let bgRect = NSRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 22, yRadius: 22)
        ctx.saveGState()
        bgPath.addClip()

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.15, green: 0.15, blue: 0.22, alpha: 1),
                CGColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1)
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 64, y: 128),
                               end: CGPoint(x: 64, y: 0),
                               options: [])
        ctx.restoreGState()

        // Hexagon grid icon from SF Symbol
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
        guard let symbolImage = NSImage(systemSymbolName: "circle.hexagongrid.fill",
                                        accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) else {
            image.unlockFocus()
            return image
        }

        let symbolRect = NSRect(
            x: (size.width - 64) / 2,
            y: (size.height - 64) / 2,
            width: 64, height: 64
        )

        // Tint with accent color
        let tinted = symbolImage.copy() as! NSImage
        tinted.lockFocus()
        NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0).set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        image.unlockFocus()
        return image
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid",
                                     accessibilityDescription: "token_hud")
        item.button?.image?.size = NSSize(width: 16, height: 16)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.action = #selector(statusBarButtonClicked(_:))
        item.button?.target = self
        statusItem = item
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = buildMenu()
            statusItem?.menu = menu
            sender.menu = menu
            sender.performClick(nil)
            // Clear menu after showing so left-click works next time
            DispatchQueue.main.async { [weak self] in
                self?.statusItem?.menu = nil
            }
        } else {
            statusItem?.menu = nil
            openSettings()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())

        let panelItem = NSMenuItem(
            title: "Toggle Floating Panel",
            action: #selector(toggleFloatingPanel),
            keyEquivalent: "f"
        )
        panelItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(panelItem)
        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        if #available(macOS 13, *) {
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(launchItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit token_hud",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    // MARK: - Floating Panel

    @objc private func toggleFloatingPanel() {
        floatingPanelManager.toggle()
    }

    // MARK: - Settings

    private func openSettingsOnFirstLaunchIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Defaults.didOpenSettingsOnFirstLaunch) else { return }
        UserDefaults.standard.set(true, forKey: Defaults.didOpenSettingsOnFirstLaunch)
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    @objc private func openSettings() {
        if let wc = settingsController, wc.window?.isVisible == true {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow()
            .environment(widgetStore)
            .environment(stateWatcher)
            .environment(appFilterStore)
            .environment(codexFetcher)
            .environment(apiPlatformFetcher)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "token_hud Settings"
        win.center()
        win.contentView = NSHostingView(rootView: settingsView)
        win.isReleasedWhenClosed = false

        let wc = NSWindowController(window: win)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsController = wc
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            statusItem?.menu = buildMenu()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
