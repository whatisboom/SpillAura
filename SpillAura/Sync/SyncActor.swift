import Foundation

/// Owns a reference to the active EntertainmentSession in its own concurrency domain.
actor SyncActor {

    private var session: EntertainmentSession?

    func setSession(_ session: EntertainmentSession) {
        self.session = session
    }

    func clearSession() {
        session = nil
    }
}
