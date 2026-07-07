import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tokenHud"

    /// Codex fetcher logs (local usage, admin extras, JWT).
    static let codex = Logger(subsystem: subsystem, category: "codex")

    /// API platform fetcher logs (DeepSeek, MiniMax, MiMo, OpenAI, etc.).
    static let apiPlatform = Logger(subsystem: subsystem, category: "apiPlatform")

    /// Notch host panel diagnostics (geometry, state transitions, hover).
    static let notchHost = Logger(subsystem: subsystem, category: "notchHost")
}
