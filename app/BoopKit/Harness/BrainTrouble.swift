import Foundation
import MellowHarness

/// Jev failing for long enough that the popover says so, to the key's
/// owner: Jev isn't helping, and every Moment still plays on the rules'
/// answers (`SeatedBrain`). With no key there's none.
public struct BrainTrouble: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The server turned the key down (HTTP 401 or 403).
        case key
        /// The account is out of credit (HTTP 402).
        case credit
        /// Anything else, `inARow` times running.
        case failing
    }

    public var kind: Kind
    /// Why Jev failed the last pass, such as `jev: HTTP 402`.
    public var why: String
    /// Passes Jev failed in a row, this one included.
    public var inARow: Int

    public init(kind: Kind, why: String, inARow: Int) {
        self.kind = kind
        self.why = why
        self.inARow = inARow
    }

    /// Failures that fix themselves (a slow answer, a busy server) show
    /// only once Jev has failed this many passes in a row.
    public static let showAfter = 3

    /// After a pass that asked Jev: nil once it answers in time; at once
    /// for a status only the person can fix; else after `showAfter` in a
    /// row.
    static func after(_ error: BrainError?, previous: Int) -> (inARow: Int, trouble: BrainTrouble?) {
        guard let error else { return (0, nil) }
        let inARow = previous + 1
        switch error.status {
        case 401, 403: return (inARow, BrainTrouble(kind: .key, why: error.description, inARow: inARow))
        case 402: return (inARow, BrainTrouble(kind: .credit, why: error.description, inARow: inARow))
        default:
            return (inARow, inARow >= showAfter ? BrainTrouble(kind: .failing, why: error.description, inARow: inARow) : nil)
        }
    }
}
