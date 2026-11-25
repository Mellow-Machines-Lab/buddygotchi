import AppKit
import BoopKit
import SwiftUI

/// The latest picture an agent showed (documentation/design/screen-guide.md,
/// "The show"): as the board will hold it up, a dark window in its agent's
/// lane colour, "claude wants to show you" on its bar, the headline in Boop's
/// words and the agent's picture under it. A tap opens its link.
struct ShowCard: View {
    let shown: Core.Shown

    private var lane: String { Palette.lanes[(shown.slot ?? 0) % Palette.lanes.count] }

    /// The picture: the agent's SVG with `currentColor` as its lane colour
    /// and Boop's mono face for its words, or its PNG. Made once a show:
    /// the Overview draws the card again at every status while it's up.
    private var picture: NSImage? {
        if let kept = Self.kept, kept.shown == shown { return kept.image }
        let image: NSImage?
        if let svg = shown.show.svg {
            let drawn = svg.replacingOccurrences(of: "currentColor", with: lane)
                .replacingOccurrences(of: "<svg ", with: "<svg font-family=\"Menlo, monospace\" ")
            image = NSImage(data: Data(drawn.utf8))
        } else {
            image = shown.show.image.flatMap(NSImage.init(contentsOfFile:))
        }
        Self.kept = (shown, image)
        return image
    }

    @MainActor private static var kept: (shown: Core.Shown, image: NSImage?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(shown.agent) wants to show you")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Color(hex: "#06201F"))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: lane))
            Text(shown.show.headline)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color(hex: "#E8E6E0"))
                .padding(.horizontal, 12).padding(.top, 8)
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(CGFloat(Show.width) / CGFloat(Show.height), contentMode: .fit)
                    .padding(8)
                    .accessibilityLabel(shown.show.headline)
            }
        }
        .background(Color(hex: "#12161B"))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: lane), lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { if let link = shown.show.link { _ = CardTool.open(link) } }
        .help(shown.show.link.map { "Open \($0)" } ?? shown.project)
    }
}
