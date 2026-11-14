import BoopKit
import SwiftUI

/// The world as a band of time zones, UTC−12 at the left to UTC+14 at the
/// right: the night side shaded from the time now, a moon at midnight and
/// a sun at noon, every buddy a dot at its offset, spread a little so they
/// don't stack, and you marked in a lane of your own along the top. Under
/// it, a footer with each region's name and how many are awake there, and
/// a legend of the kinds of dot it shows. A click picks the nearest buddy.
/// A buddy with no offset has no place on it.
struct WorldBand: View {
    let buddies: [World.Buddy]
    /// How many are awake, as the world counts them: more than the dots.
    var awake: Int
    /// How many are awake in each region, for the footer; nil while the
    /// world isn't known.
    var regions: [World.RegionCount]?
    /// Your own buddy's id in the world: its dot is ringed.
    var me: String?
    /// Your UTC offset, in minutes, and whether you're in the world: out of
    /// it, "you" is dim.
    let you: Int
    var youIn = true
    @Binding var pick: String?
    /// Words on the empty band while there's no world to show, and whether
    /// they say something is wrong.
    var message: String? = nil
    var trouble = false
    var now = Date()
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 100
    /// The top of the band is a lane for "you" and the sun and moon only.
    static let lane: CGFloat = 18
    static let footer: CGFloat = 22
    /// The offsets the band spans, in hours.
    static let west = -12.0, east = 14.0
    private static let inset: CGFloat = 8
    /// How close two dots' centres may come before one is moved.
    static let apart: CGFloat = 7
    /// With this many buddies or fewer, each dot has its name.
    static let named = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let size = geo.size
                    Canvas { context, size in
                        let spots = layout(in: size)
                        shadeNight(context, size)
                        sunAndMoon(context, size)
                        youLine(context, size)
                        draw(context, spots)
                        youLabel(context, size)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        pick = nearest(to: location, in: size)
                    }
                    .overlay {
                        if let message {
                            HStack(alignment: .firstTextBaseline, spacing: Theme.gapTight) {
                                if trouble { Image(systemName: "exclamationmark.triangle") }
                                Text(message).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.body).foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius).strokeBorder(Theme.hairline, lineWidth: 1))
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Self.lane)
                        }
                    }
                }
                .frame(height: Self.height)
                .background(Theme.well)
                Hairline()
                footerStrip
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.wellRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius).strokeBorder(Theme.hairline, lineWidth: 1))
            .help(placed.isEmpty ? "" : "Click a buddy to see it.")
            if !placed.isEmpty { legend }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message ?? "\(awake.formatted()) buddies awake around the world")
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

    /// Every placed buddy's spot: across by its offset and a little by a
    /// second hash, so a zone isn't a column; down by its id, below the
    /// lane; then moved up or down, in order of id, until it is `apart`
    /// from the dots already placed, if there's room. The same each time.
    func layout(in size: CGSize) -> [(buddy: World.Buddy, at: CGPoint)] {
        let top = Self.lane + 6, bottom = size.height - 8
        let hour = (size.width - 2 * Self.inset) / CGFloat(Self.east - Self.west)
        var spots: [(buddy: World.Buddy, at: CGPoint)] = []
        for buddy in placed.sorted(by: { $0.id < $1.id }) {
            let hours = Double(buddy.utcOffset ?? 0) / 60
            let x = x(hours: hours, in: size) + hour * 0.7 * CGFloat(Self.spread(buddy.id + "/x") - 0.5)
            let y = top + (bottom - top) * CGFloat(Self.spread(buddy.id))
            let free = { (p: CGPoint) in spots.allSatisfy { hypot($0.at.x - p.x, $0.at.y - p.y) >= Self.apart } }
            let tries = [0, 1, -1, 2, -2, 3, -3, 4, -4].map { CGPoint(x: x, y: y + CGFloat($0) * Self.apart) }
                .filter { $0.y >= top && $0.y <= bottom }
            spots.append((buddy, tries.first(where: free) ?? CGPoint(x: x, y: y)))
        }
        return spots
    }

    /// 0 to 1 from an id, steady from launch to launch, which Swift's own
    /// hash isn't.
    static func spread(_ id: String) -> Double {
        var mix = SplitMix64(seed: SplitMix64.seed(of: id))
        return Double(mix.next() % 10_000) / 10_000
    }

    static let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    private func nearest(to point: CGPoint, in size: CGSize) -> String? {
        let near = layout(in: size).map { ($0.buddy.id, hypot($0.at.x - point.x, $0.at.y - point.y)) }.min { $0.1 < $1.1 }
        guard let near, near.1 < 14 else { return nil }
        return near.0
    }

    /// The hour it is in UTC now, with minutes as a fraction.
    private var utcHour: Double {
        let utc = Self.utc.dateComponents([.hour, .minute], from: now)
        return Double(utc.hour ?? 0) + Double(utc.minute ?? 0) / 60
    }

    // MARK: Drawing

    /// How dark it is at a local hour: 0 by day, 1 at night, with an
    /// hour or so of dusk and dawn between.
    static func darkness(localHour h: Double) -> Double {
        let sun = cos(2 * .pi * (h - 12.5) / 24)
        return max(0, min(1, (0.15 - sun) * 3))
    }

    private func shadeNight(_ context: GraphicsContext, _ size: CGSize) {
        let hour = utcHour
        let night = scheme == .dark ? Color(hex: "#05070D").opacity(0.8) : Color(hex: "#3B3328").opacity(0.2)
        // One gradient across the band, a stop every few points: strips
        // side by side would show their seams. The insets at each end hold
        // the edge's own shade, not the hour past the band's end.
        let usable = Double(size.width - 2 * Self.inset)
        let stops = stride(from: 0.0, through: 1.0, by: 1.0 / 120).map { at -> Gradient.Stop in
            let x = min(max(Double(size.width) * at - Double(Self.inset), 0), usable)
            let hours = Self.west + (Self.east - Self.west) * x / usable
            let local = (hour + hours).truncatingRemainder(dividingBy: 24)
            return .init(color: night.opacity(Self.darkness(localHour: local < 0 ? local + 24 : local)), location: at)
        }
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
    }

    /// The offsets, in hours on the band, where it's now `local` o'clock.
    private func offsets(where local: Double) -> [Double] {
        let base = local - utcHour
        return (-2...2).map { base + Double($0) * 24 }.filter { $0 >= Self.west && $0 <= Self.east }
    }

    /// A moon in the lane where it's midnight, a sun where it's noon, out
    /// of the way of "you".
    private func sunAndMoon(_ context: GraphicsContext, _ size: CGSize) {
        let youX = x(hours: Double(you) / 60, in: size)
        for (local, symbol) in [(0.0, "moon.fill"), (12.0, "sun.max.fill")] {
            for hours in offsets(where: local) {
                let at = x(hours: hours, in: size)
                guard abs(at - youX) > 22 else { continue }
                var mark = context.resolve(Image(systemName: symbol))
                mark.shading = .color(Theme.inkSoft)
                context.draw(mark, in: CGRect(x: at - 4.5, y: 4.5, width: 9, height: 9))
            }
        }
    }

    private var youX: (CGSize) -> CGFloat { { x(hours: Double(you) / 60, in: $0) } }

    /// Your line down the band, under the dots.
    private func youLine(_ context: GraphicsContext, _ size: CGSize) {
        let ink = youIn ? Theme.ink : Theme.inkSoft
        context.fill(Path(CGRect(x: youX(size) - 0.5, y: Self.lane, width: 1, height: size.height - Self.lane)),
                     with: .color(ink.opacity(youIn ? 0.3 : 0.2)))
    }

    /// "you", alone in the lane.
    private func youLabel(_ context: GraphicsContext, _ size: CGSize) {
        let ink = youIn ? Theme.ink : Theme.inkSoft
        context.draw(Text("you").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink),
                     at: CGPoint(x: youX(size), y: Self.lane / 2))
    }

    /// The dots, asleep under awake, and your own and the picked one on
    /// top, each ringed; with a few buddies, their names.
    private func draw(_ context: GraphicsContext, _ spots: [(buddy: World.Buddy, at: CGPoint)]) {
        let rank = { (b: World.Buddy) -> Int in
            b.id == pick ? 3 : b.id == me ? 2 : b.activity == .asleep ? 0 : 1
        }
        let ordered = spots.enumerated().sorted { (rank($0.element.buddy), $0.offset) < (rank($1.element.buddy), $1.offset) }.map(\.element)
        for spot in ordered {
            dot(context, spot.buddy, at: spot.at)
            if spot.buddy.id == pick {
                ring(context, at: spot.at, radius: 7, width: 1.5, opacity: 1)
            } else if spot.buddy.id == me {
                ring(context, at: spot.at, radius: 5.5, width: 1, opacity: 0.6)
            }
        }
        guard spots.count <= Self.named else { return }
        for spot in spots {
            // Right of the dot, unless that runs off the band or over another dot.
            let width = CGFloat(spot.buddy.name.count) * 6 + 8
            let covers = { (dx: CGFloat) in
                spots.contains { other in
                    other.buddy.id != spot.buddy.id && abs(other.at.y - spot.at.y) < 10
                        && (dx > 0 ? other.at.x > spot.at.x && other.at.x < spot.at.x + width
                                   : other.at.x < spot.at.x && other.at.x > spot.at.x - width)
                }
            }
            let fitsRight = spot.at.x + width < context.clipBoundingRect.width - 4
            let fitsLeft = spot.at.x - width > 4
            let right = fitsRight && (!covers(1) || !fitsLeft || covers(-1))
            context.draw(Text(spot.buddy.name).font(.chip).foregroundStyle(Theme.inkSoft),
                         at: CGPoint(x: spot.at.x + (right ? 7 : -7), y: spot.at.y), anchor: right ? .leading : .trailing)
        }
    }

    private func ring(_ context: GraphicsContext, at p: CGPoint, radius r: CGFloat, width: CGFloat, opacity: Double) {
        context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Theme.ink.opacity(opacity)), lineWidth: width)
    }

    /// Awake, a dot in its kind's colour, outlined in ink on light paper;
    /// asleep, a hollow ring, which shows on either side of the night.
    private func dot(_ context: GraphicsContext, _ buddy: World.Buddy, at p: CGPoint) {
        if buddy.activity == .asleep {
            let r: CGFloat = 2.5
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Theme.inkSoft), lineWidth: 1)
            return
        }
        let r: CGFloat = 3
        let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        context.fill(path, with: .color(Self.colour(buddy.activity)))
        if scheme == .light { context.stroke(path, with: .color(Theme.ink.opacity(0.35)), lineWidth: 0.75) }
    }

    /// An awake buddy's colour, by what it's doing.
    static func colour(_ activity: World.Activity) -> Color {
        switch activity {
        case .coding: Theme.lane(0) ?? Theme.sage
        case .testing: Theme.lane(2) ?? Theme.sage
        case .shipping: Theme.amber
        case .waiting: Theme.blush
        case .idle: Theme.sage
        case .asleep: Theme.inkSoft
        }
    }

    // MARK: The footer and the legend

    /// The hour on the band where each region starts: half way between
    /// its first offset and the one before.
    static func start(_ region: World.Region) -> Double {
        switch region {
        case .americas: west
        case .europeAfrica: -1.875
        case .asiaOceania: 3.125
        }
    }

    /// A region's name when its part of the band is narrow.
    static func shortName(_ region: World.Region) -> String {
        switch region {
        case .americas: "Americas"
        case .europeAfrica: "Eur · Afr"
        case .asiaOceania: "Asia"
        }
    }

    /// A region's name in the fewest letters.
    static func shortest(_ region: World.Region) -> String {
        switch region {
        case .americas: "Am"
        case .europeAfrica: "Eur"
        case .asiaOceania: "Asia"
        }
    }

    /// Each region's name and count, left-aligned under its own part of
    /// the band, a hairline tick where each but the first starts.
    private var footerStrip: some View {
        GeometryReader { geo in
            let all = World.Region.allCases
            ForEach(Array(all.enumerated()), id: \.element) { i, region in
                let from = i == 0 ? 0 : x(hours: Self.start(region), in: geo.size)
                let to = i + 1 < all.count ? x(hours: Self.start(all[i + 1]), in: geo.size) : geo.size.width
                if i > 0 {
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: geo.size.height).position(x: from, y: geo.size.height / 2)
                }
                // Its words start a little after the tick, the first at the band's inset.
                let lead: CGFloat = i == 0 ? Self.inset : 4
                regionLabel(region)
                    .frame(width: max(0, to - from - lead - 2), alignment: .leading)
                    .position(x: from + lead + max(0, to - from - lead - 2) / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: Self.footer)
        .background(Theme.raised)
    }

    private func regionLabel(_ region: World.Region) -> some View {
        let count = regions.map { r in (r.first { $0.region == region }?.awake ?? 0).formatted() } ?? "–"
        return ViewThatFits(in: .horizontal) {
            ForEach(Array([region.name, Self.shortName(region), Self.shortest(region), ""].enumerated()), id: \.offset) { _, name in
                (Text(name.isEmpty ? "" : name + " ").foregroundStyle(Theme.inkSoft) + Text(count).fontWeight(.semibold))
                    .font(.chip).fixedSize()
            }
        }
        .accessibilityLabel("\(region.name): \(count) awake")
    }

    /// The kinds of dot the band shows, in the legend's order.
    static let kinds: [World.Activity] = [.coding, .testing, .shipping, .waiting, .idle, .asleep]

    /// One row of the kinds present: a 6 pt dot and the word, asleep hollow.
    private var legend: some View {
        let present = Self.kinds.filter { kind in placed.contains { $0.activity == kind } }
        return HStack(spacing: Theme.gapSnug + 2) {
            ForEach(present, id: \.self) { kind in
                HStack(spacing: Theme.gapTight) {
                    if kind == .asleep {
                        Circle().strokeBorder(Theme.inkSoft, lineWidth: 1).frame(width: 6, height: 6)
                    } else {
                        Circle().fill(Self.colour(kind)).frame(width: 6, height: 6)
                    }
                    Text(kind == .idle ? "resting" : kind.rawValue).font(.chip).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(.leading, Theme.hair)
        .accessibilityElement(children: .combine)
    }
}
