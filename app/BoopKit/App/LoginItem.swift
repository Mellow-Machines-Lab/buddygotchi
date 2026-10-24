import Foundation
import ServiceManagement

/// Opening Boop when you log in: macOS's login item for the app, which only
/// an app bundle can be. Setup turns it on; Settings has the switch.
public struct LoginItem: Sendable {
    public enum State: Equatable, Sendable {
        case on, off
        /// Turned on, but macOS waits for the person to allow it in System
        /// Settings, under General, Login Items.
        case needsApproval
        /// Not an app bundle (`make run`'s bare binary), so macOS can't
        /// open it at login.
        case unavailable
    }

    public var state: @Sendable () -> State
    /// Turns it on or off. Throws macOS's reason when it can't.
    public var set: @Sendable (Bool) throws -> Void

    public init(state: @escaping @Sendable () -> State, set: @escaping @Sendable (Bool) throws -> Void) {
        self.state = state
        self.set = set
    }

    /// The app's own login item, when it's an app bundle at `bundleURL`.
    public static func system(bundleURL: URL = Bundle.main.bundleURL) -> LoginItem {
        guard bundleURL.pathExtension == "app" else { return unavailable }
        return LoginItem(state: {
            switch SMAppService.mainApp.status {
            case .enabled: .on
            case .requiresApproval: .needsApproval
            default: .off
            }
        }, set: { on in
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        })
    }

    public static let unavailable = LoginItem(state: { .unavailable }, set: { _ in })

    /// System Settings, at Login Items.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
