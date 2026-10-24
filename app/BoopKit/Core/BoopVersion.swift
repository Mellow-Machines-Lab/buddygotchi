import CBoopVersion
import Foundation

/// The app's version, shown in the popover, `--help` and bug reports: the
/// repo's VERSION file, compiled in, which the firmware's version comes
/// from too.
public enum BoopVersion {
    public static let current = String(cString: boop_version()).trimmingCharacters(in: .whitespacesAndNewlines)
}
