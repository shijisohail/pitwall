import Foundation
import os

/// Unified logging (Console.app / `log stream --predicate 'subsystem == "<bundle id>"'`).
/// Never log prompts, file paths or transcript content: dynamic strings stay `.private` by default.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "Pitwall"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let cli = Logger(subsystem: subsystem, category: "cli")
    static let history = Logger(subsystem: subsystem, category: "history")
}
