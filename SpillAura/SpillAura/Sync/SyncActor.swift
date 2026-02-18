import Foundation

/// Owns the EntertainmentSession and serializes all access to it.
///
/// `SyncActor` runs in its own concurrency domain (Swift actor isolation).
/// In M2 it provides a simple one-shot color sender.
/// In M3 it will drive a real-time animation loop.
actor SyncActor {

    private var session: EntertainmentSession?

    // MARK: - Session lifecycle

    /// Attach a session that is already started (or starting).
    /// Call this before `sendStaticColor`.
    func setSession(_ session: EntertainmentSession) {
        self.session = session
    }

    /// Remove and stop the current session.
    func clearSession() {
        session = nil
    }

    // MARK: - Color sending

    /// Send a single static color packet to all channels.
    ///
    /// Does nothing if no session is attached or if the session is not
    /// in the `.streaming` state.
    func sendStaticColor(r: Float, g: Float, b: Float) async {
        let currentSession = session
        await MainActor.run {
            currentSession?.sendColor(r: r, g: g, b: b)
        }
    }
}
