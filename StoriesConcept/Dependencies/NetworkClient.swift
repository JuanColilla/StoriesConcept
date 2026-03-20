import ComposableArchitecture
import Foundation
import Network
import os

@DependencyClient
struct NetworkClient: Sendable {
    var start: @Sendable () -> Void = { }
    var stop: @Sendable () -> Void = { }
    var isConnected: @Sendable () -> Bool = { true }
    var observeConnectivity: @Sendable () -> AsyncStream<Bool> = { .finished }
}

extension NetworkClient: DependencyKey {
    static let liveValue: NetworkClient = {
        let monitor = NetworkMonitorLive()
        return NetworkClient(
            start: { monitor.start() },
            stop: { monitor.stop() },
            isConnected: { monitor.currentStatus },
            observeConnectivity: { monitor.connectivityStream() }
        )
    }()

    static let previewValue = NetworkClient(
        start: { },
        stop: { },
        isConnected: { true },
        observeConnectivity: {
            AsyncStream { $0.yield(true) }
        }
    )
}

extension DependencyValues {
    var networkClient: NetworkClient {
        get { self[NetworkClient.self] }
        set { self[NetworkClient.self] = newValue }
    }
}

// MARK: - Live Implementation

/// @Observable wrapper around NWPathMonitor.
/// Demonstrates Apple's Observation framework alongside TCA's @ObservableState.
@Observable
final class NetworkMonitorLive: @unchecked Sendable {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let lock = NSLock()

    var currentStatus: Bool {
        lock.withLock { isConnected }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            Task { @MainActor in
                self.isConnected = connected
            }
            let conts = self.lock.withLock { Array(self.continuations.values) }
            for continuation in conts {
                continuation.yield(connected)
            }
            Logger.network.info("Connectivity: \(connected ? "online" : "offline", privacy: .public)")
        }
        monitor.start(queue: queue)
        Logger.network.info("Network monitor started")
    }

    func stop() {
        monitor.cancel()
        let conts = lock.withLock {
            let vals = Array(continuations.values)
            continuations.removeAll()
            return vals
        }
        conts.forEach { $0.finish() }
    }

    func connectivityStream() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.lock.withLock {
                self.continuations[id] = continuation
            }
            continuation.yield(self.lock.withLock { self.isConnected })
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }
}
