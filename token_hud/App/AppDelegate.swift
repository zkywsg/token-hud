// token_hud/App/AppDelegate.swift
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var stateWatcher: StateWatcher!
    private var widgetStore: WidgetStore!
    private var windowManager: NotchWindowManager!
    private var statusItem: NSStatusItem?
    private var settingsController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        stateWatcher  = StateWatcher()
        widgetStore   = WidgetStore()
        stateWatcher.start()

        windowManager = NotchWindowManager(stateWatcher: stateWatcher, widgetStore: widgetStore)
        windowManager.setup()

        setupStatusBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateWatcher.stop()
        windowManager.teardown()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid",
                                     accessibilityDescription: "token_hud")
        item.button?.image?.size = NSSize(width: 16, height: 16)
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
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

    // MARK: - Settings

    @objc private func openSettings() {
        if let wc = settingsController, wc.window?.isVisible == true {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow().environmentObject(widgetStore)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
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
