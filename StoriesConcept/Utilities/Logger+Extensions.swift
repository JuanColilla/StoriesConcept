import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let api = Logger(subsystem: subsystem, category: "API")
    static let cache = Logger(subsystem: subsystem, category: "Cache")
    static let player = Logger(subsystem: subsystem, category: "Player")
    static let list = Logger(subsystem: subsystem, category: "List")
    static let persist = Logger(subsystem: subsystem, category: "Persistence")
    static let prefetch = Logger(subsystem: subsystem, category: "Prefetch")
    static let network = Logger(subsystem: subsystem, category: "Network")
}
