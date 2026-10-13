import Foundation
import Observation
import WidgetKit
@preconcurrency import WatchConnectivity

/// Today's numbers from Leanr on iPhone, and the way back to it. The last snapshot is kept on the watch so it shows
/// something useful even when the iPhone is out of reach; anything logged meanwhile is queued and sent when it's back.
@MainActor @Observable
final class WatchModel: NSObject {
    private(set) var snapshot: WatchSnapshot?
    /// Set briefly after a tap, for the confirmation.
    var confirmation: String?

    override init() {
        super.init()
        snapshot = WatchStorage.read()
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

    /// Keeps the snapshot where the complications can read it, and redraws them when what they show has changed.
    private func update(_ value: WatchSnapshot) {
        let changed = WatchStorage.complicationsDiffer(snapshot, value)
        snapshot = value
        WatchStorage.write(value)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Lets the system wake the app for an update from the iPhone and finish taking it in before it sleeps again.
    func finishTransfers() async {
        for _ in 0..<20 where WCSession.default.hasContentPending {
            try? await Task.sleep(for: .milliseconds(250))
        }
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
    /// Complication updates, which the iPhone sends when one of Leanr's complications is on the watch face.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let value = WatchSnapshot(context: userInfo) else { return }
        Task { @MainActor in self.received(value) }
    }
}
