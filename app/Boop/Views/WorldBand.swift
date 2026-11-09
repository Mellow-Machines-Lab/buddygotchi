import BoopKit
import SwiftUI

/// The world as a band of time zones, UTC−12 at the left to UTC+14 at the
/// right: the night side shaded from the time now, every buddy a dot at
/// its offset, spread up and down so they don't stack, awake ones bright,
/// and you marked. A click picks the nearest buddy. A buddy with no
/// offset has no place on it.
struct WorldBand: View {
    let buddies: [World.Buddy]
    /// How many are awake, as the world counts them: more than the dots.
    var awake: Int
    /// Your own buddy's id in the world: its dot is ringed.
    var me: String?
    /// Your UTC offset, in minutes, and whether you're in the world: out of
    /// it, "you" is dim.
    let you: Int
    var youIn = true
    @Binding var pick: String?
    var now = Date()
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 96
    /// The offsets the band spans, in hours.
    static let west = -12.0, east = 14.0
    private static let inset: CGFloat = 8

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let size = geo.size
                Canvas { context, size in
                    shadeNight(context, size)
                    for buddy in placed { dot(context, buddy, at: place(buddy, in: size)) }
                    if let me, let buddy = placed.first(where: { $0.id == me }) {
                        let p = place(buddy, in: size)
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                                       with: .color(Theme.ink.opacity(0.6)), lineWidth: 1)
                    }
                    if let pick, let buddy = placed.first(where: { $0.id == pick }) {
                        let p = place(buddy, in: size)
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                                       with: .color(Theme.ink), lineWidth: 1.5)
                    }
                    youMark(context, size)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    pick = nearest(to: location, in: size)
                }
            }
            .frame(height: Self.height)
            .background(Theme.well)
            .clipShape(RoundedRectangle(cornerRadius: Theme.wellRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius).strokeBorder(Theme.hairline, lineWidth: 1))
            regions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(awake.formatted()) buddies awake around the world")
        // VoiceOver can't click a dot: the first awake buddies as buttons.
        .accessibilityChildren {
            ForEach(placed.filter { $0.activity != .asleep }.prefix(20)) { buddy in
                Button(buddy.id == me ? "\(buddy.name), you" : buddy.name) { pick = buddy.id }
            }
        }
    }

    /// The buddies with a place on the band.
    private var placed: [World.Buddy] { buddies.filter { $0.utcOffset != nil } }

    // MARK: Where things go

    /// How far across the band an offset in hours is, 0 to 1.
    static func across(hours: Double) -> Double { (hours - west) / (east - west) }

    private func x(hours: Double, in size: CGSize) -> CGFloat {
        Self.inset + (size.width - 2 * Self.inset) * Self.across(hours: hours)
    }

    /// A buddy's place: across by its offset, up and down by its id, the
    /// same each time.
    private func place(_ buddy: World.Buddy, in size: CGSize) -> CGPoint {
        let hours = Double(buddy.utcOffset ?? 0) / 60
        let height = size.height - 2 * Self.inset - 6
        return CGPoint(x: x(hours: hours, in: size), y: Self.inset + 6 + height * Self.spread(buddy.id))
    }

    /// 0 to 1 from an id, steady from launch to launch, which Swift's own
    /// hash isn't.
    static func spread(_ id: String) -> Double {
        var mix = SplitMix64(seed: SplitMix64.seed(of: id))
        return Double(mix.next() % 10_000) / 10_000
    }

    static let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    private func nearest(to point: CGPoint, in size: CGSize) -> String? {
        let near = placed.map { b -> (String, CGFloat) in
            let p = place(b, in: size)
            return (b.id, hypot(p.x - point.x, p.y - point.y))
        }.min { $0.1 < $1.1 }
        guard let near, near.1 < 14 else { return nil }
        return near.0
    }

    // MARK: Drawing

    /// How dark it is at a local hour: 0 by day, 1 at night, with an
    /// hour or so of dusk and dawn between.
    static func darkness(localHour h: Double) -> Double {
        let sun = cos(2 * .pi * (h - 12.5) / 24)
        return max(0, min(1, (0.15 - sun) * 3))
    }

    private func shadeNight(_ context: GraphicsContext, _ size: CGSize) {
        let utc = Self.utc.dateComponents([.hour, .minute, .second], from: now)
        let hour = Double(utc.hour ?? 0) + Double(utc.minute ?? 0) / 60
        let night = scheme == .dark ? Color(hex: "#05070D").opacity(0.8) : Color(hex: "#3B3328").opacity(0.2)
        // One gradient across the band, a stop every few points: strips
        // side by side would show their seams.
        let stops = stride(from: 0.0, through: 1.0, by: 1.0 / 120).map { at -> Gradient.Stop in
            let x = Double(size.width) * at
            let hours = Self.west + (Self.east - Self.west) * (x - Double(Self.inset)) / Double(size.width - 2 * Self.inset)
            let local = (hour + hours).truncatingRemainder(dividingBy: 24)
            return .init(color: night.opacity(Self.darkness(localHour: local < 0 ? local + 24 : local)), location: at)
        }
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
    }

    private func dot(_ context: GraphicsContext, _ buddy: World.Buddy, at p: CGPoint) {
        let awake = buddy.activity != .asleep
        let r: CGFloat = awake ? 3 : 2.5
        // Asleep, a dim dot that still shows on the night side, dark or light.
        let colour = awake ? Self.colour(buddy.activity) : scheme == .dark ? Theme.inkSoft.opacity(0.55) : Theme.inkFaint.opacity(0.7)
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(colour))
    }

    /// An awake buddy's colour, by what it's doing.
    static func colour(_ activity: World.Activity) -> Color {
        switch activity {
        case .coding: Theme.lane(0) ?? Theme.sage
        case .testing: Theme.lane(2) ?? Theme.sage
        case .shipping: Theme.amber
        case .waiting: Theme.blush
        case .idle: Theme.sage
        case .asleep: Theme.inkFaint
        }
    }

    /// You: a line down the band at your offset, and the word.
    private func youMark(_ context: GraphicsContext, _ size: CGSize) {
        let x = x(hours: Double(you) / 60, in: size)
        let ink = youIn ? Theme.ink : Theme.inkFaint
        context.fill(Path(CGRect(x: x - 0.5, y: 14, width: 1, height: size.height - 18)), with: .color(ink.opacity(youIn ? 0.35 : 0.25)))
        context.draw(Text("you").font(.system(size: 9, weight: .semibold)).foregroundStyle(ink), at: CGPoint(x: x, y: 7))
    }

    /// The three regions' names under the band, each under its middle.
    private var regions: some View {
        GeometryReader { geo in
            ForEach(World.Region.allCases, id: \.self) { region in
                Text(region.name)
                    .font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
                    .fixedSize()
                    .position(x: x(hours: Self.middle(region), in: geo.size), y: geo.size.height / 2)
            }
        }
        .frame(height: 12)
    }

    /// The middle of a region's offsets, in hours.
    static func middle(_ region: World.Region) -> Double {
        switch region {
        case .americas: -6.5
        case .europeAfrica: 1
        case .asiaOceania: 8.5
        }
    }
}
