import os

extension Logger {
    static let api = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "API")
    static let cache = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "Cache")
    static let player = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "Player")
    static let list = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "List")
    static let persist = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "Persistence")
    static let prefetch = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "Prefetch")
    static let network = Logger(subsystem: "com.juancolilla.StoriesConcept", category: "Network")
}
