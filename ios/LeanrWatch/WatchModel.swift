import Foundation
import Observation
@preconcurrency import WatchConnectivity

/// Today's numbers from Leanr on iPhone, and the way back to it. The last snapshot is kept on the watch so it shows
/// something useful even when the iPhone is out of reach; anything logged meanwhile is queued and sent when it's back.
@MainActor @Observable
final class WatchModel: NSObject {
    private(set) var snapshot: WatchSnapshot?
    /// Set briefly after a tap, for the confirmation.
    var confirmation: String?
    private static let storageKey = "watch.snapshot"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// The snapshot for today, so yesterday's totals never show as today's.
    var today: WatchSnapshot? { snapshot?.current() }

    func log(_ option: WatchSnapshot.Option) {
        guard let today else { return }
        update(today.logging(option))
        send(.log(option.id))
        confirmation = "Logged \(option.name)"
    }

    func addWater(_ millilitres: Double) {
        guard let today else { return }
        update(today.addingWater(millilitres))
        send(.water(millilitres))
    }

    private func update(_ value: WatchSnapshot) {
        snapshot = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }

    /// Straight away when the iPhone is reachable, otherwise queued until it is.
    private func send(_ request: WatchRequest) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(request.message, replyHandler: nil) { _ in WCSession.default.transferUserInfo(request.message) }
        } else {
            session.transferUserInfo(request.message)
        }
    }

    fileprivate func received(_ value: WatchSnapshot) { update(value) }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let value = WatchSnapshot(context: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.received(value) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let value = WatchSnapshot(context: applicationContext) else { return }
        Task { @MainActor in self.received(value) }
    }
}
