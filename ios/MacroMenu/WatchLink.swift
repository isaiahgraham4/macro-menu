import Foundation
@preconcurrency import WatchConnectivity

/// Keeps Leanr on Apple Watch up to date and logs what's tapped there. Everything goes directly between the iPhone and
/// the paired watch; nothing passes through a server.
@MainActor final class WatchLink: NSObject {
    static let shared = WatchLink()
    private weak var store: AppStore?
    private var lastSent: WatchSnapshot?
    private var lastComplication: WatchSnapshot?

    func start(_ store: AppStore) {
        guard WCSession.isSupported(), self.store == nil else { return }
        self.store = store
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends today's snapshot if the watch app is installed and it's changed since last time.
    func send() {
        let session = WCSession.default
        guard let store, WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let snapshot = store.watchSnapshot()
        guard snapshot != lastSent else { return }
        // A Leanr complication on the watch face gets a priority update (about 50 a day), which wakes the watch app to
        // redraw it; spent only when the calories, protein or water shown have changed.
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0,
           WatchStorage.complicationsDiffer(lastComplication, snapshot) {
            session.transferCurrentComplicationUserInfo(snapshot.context)
            lastComplication = snapshot
        }
        do { try session.updateApplicationContext(snapshot.context); lastSent = snapshot } catch {}
    }

    private func handle(_ request: WatchRequest) {
        guard let store else { return }
        switch request {
        case .log(let option):
            if store.logAgain(option) { store.notice = "Logged from Apple Watch" }
        case .water(let millilitres):
            store.addWater(millilitres)
        }
        lastSent = nil
        send()
        // The watch can wake Leanr in the background; give Apple Health time to take the change before it sleeps again.
        Task { await AppServices.health.finishPending() }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.send() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: start again with the new one.
        WCSession.default.activate()
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSent = nil; self.send() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let request = WatchRequest(message: message) else { return }
        Task { @MainActor in self.handle(request) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let request = WatchRequest(message: userInfo) else { return }
        Task { @MainActor in self.handle(request) }
    }
}
