import AppKit
import BoopKit
import SwiftUI

/// The app's palette, the device's "Warm Terminal": warm paper
/// and ink in both appearances, black glass for the face tile and the one
/// filled button (oat on dark paper), and one amber accent, for needs you
/// only. Working and idle are greys, as on the device; sage means connected
/// and on, and clay means trouble. It's hand-set rather than the system's
/// greys, because the popover belongs to an object on your desk. Every
/// `*Ink` tone clears 4.5:1 on its paper, cards, the well and its own chip
/// (`Boop --snapshots` checks); `inkFaint` doesn't and is for decoration and
/// disabled things only, never text. A colour that carries meaning as a
/// shape (a dot, a bar, a ring, a switch) clears 3:1 on what it's drawn on:
/// the device's bright colours have a darker partner on light paper.
enum Palette {
    static let paperLight = "#FAF7F2", paperDark = "#1B1815"
    static let raisedLight = "#F3EDE3", raisedDark = "#24211C"
    static let wellLight = "#EBE3D6", wellDark = "#2C2822"
    static let hairlineLight = "#E4DACA", hairlineDark = "#38332B"
    static let hairlineStrongLight = "#D6C8B2", hairlineStrongDark = "#4A4339"
    static let inkLight = "#24211C", inkDark = "#F2EBE0"
    static let inkSoftLight = "#675F53", inkSoftDark = "#ADA396"
    static let inkFaintLight = "#A29888", inkFaintDark = "#787064"

    /// The device's amber (firmware `palette.h`), and text tones of it.
    static let amber = "#FFB000", amberInkLight = "#82540F", amberInkDark = "#E8B970"
    /// The menu-bar icon's amber on a light menu bar, where the device's is
    /// 1.7:1; also needs you's dot and bar on light paper.
    static let menuAmberLight = "#B87400"
    static let sage = "#6E9B5E", sageInkLight = "#466638", sageInkDark = "#A3CC90"
    /// Sage as a shape on light paper (a full ring, a switch that's on),
    /// where the device's is 2.8:1 on a card.
    static let sageSignalLight = "#5E8C4F"
    /// The ring while it fills: Boop's blue, in a tone that reads on each paper.
    static let ringLight = "#2F7FD6", ringDark = "#58A6F0"
    /// A switch's track while it's off.
    static let controlOffLight = "#877D6E", controlOffDark = "#787064"
    /// What's chosen in a segmented control, raised off its well: the paper
    /// in light, a step lighter than the card in dark, where paper reads as a hole.
    static let liftedDark = "#38332B"
    static let clayInkLight = "#9C3B2E", clayInkDark = "#F09384"

    /// The device's black glass, the oat of its text, and the designs' coral
    /// cheeks (the popover's tile takes the rest of the face's colours from
    /// FaceDesigns). Glass with an oat label is the filled button on light
    /// paper; on dark paper it's the other way round.
    static let glass = "#000000", glassPressed = "#2A2620", oat = "#E8DCC4", oatPressed = "#CFC2A8"
    static let blush = "#F1787D"
    /// The work stream's lanes, by slot (firmware `stream.h`'s kLaneInk,
    /// RGB565 widened): teal, rose, lilac, lime, never needs you's amber.
    /// Only bars wear them. On light paper each has a darker partner, as
    /// the board's are 1.3 to 2.2:1 there.
    static let lanes = ["#3AD2CE", "#FF8ADE", "#B58EFF", "#9CE763"]
    static let lanesLight = ["#11847F", "#D9489F", "#8257E6", "#4E8A16"]
}

enum Theme {
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    static let paper = adaptive(Palette.paperLight, Palette.paperDark)
    static let raised = adaptive(Palette.raisedLight, Palette.raisedDark)
    static let well = adaptive(Palette.wellLight, Palette.wellDark)
    static let hairline = adaptive(Palette.hairlineLight, Palette.hairlineDark)
    static let hairlineStrong = adaptive(Palette.hairlineStrongLight, Palette.hairlineStrongDark)

    static let ink = adaptive(Palette.inkLight, Palette.inkDark)
    static let inkSoft = adaptive(Palette.inkSoftLight, Palette.inkSoftDark)
    static let inkFaint = adaptive(Palette.inkFaintLight, Palette.inkFaintDark)

    static let amber = Color(hex: Palette.amber)
    /// Needs you as a shape: a dot or a bar, which must read on light paper.
    static let amberSignal = adaptive(Palette.menuAmberLight, Palette.amber)
    /// Good as a shape: a full ring, a switch that's on.
    static let sageSignal = adaptive(Palette.sageSignalLight, Palette.sage)
    static let ring = adaptive(Palette.ringLight, Palette.ringDark)
    static let controlOff = adaptive(Palette.controlOffLight, Palette.controlOffDark)
    static let lifted = adaptive(Palette.paperLight, Palette.liftedDark)
    static let amberInk = adaptive(Palette.amberInkLight, Palette.amberInkDark)
    static let sage = Color(hex: Palette.sage)
    static let sageInk = adaptive(Palette.sageInkLight, Palette.sageInkDark)
    static let clayInk = adaptive(Palette.clayInkLight, Palette.clayInkDark)
    /// A work stream lane's colour, by its slot on the board; nil for none.
    static func lane(_ slot: Int) -> Color? {
        Palette.lanes.indices.contains(slot) ? adaptive(Palette.lanesLight[slot], Palette.lanes[slot]) : nil
    }
    /// The mic is on: macOS's own recording red, for the status dot.
    static let recording = Color(hex: "#FF3B30")

    static let glass = Color(hex: Palette.glass)
    /// A card that's dark in either appearance, for onboarding's terminal
    /// and the agent's hello: the dark card and its hairline, so the dark
    /// inks on it read and it stands off the dark paper.
    static let terminal = Color(hex: Palette.raisedDark)
    static let terminalEdge = Color(hex: Palette.hairlineDark)
    /// The filled button: black glass with an oat label on light paper. On
    /// dark paper glass would read as a hole, no heavier than an outlined
    /// button, so there it's oat with a glass label.
    static let fill = adaptive(Palette.glass, Palette.oat)
    static let fillPressed = adaptive(Palette.glassPressed, Palette.oatPressed)
    static let fillLabel = adaptive(Palette.oat, Palette.glass)
    /// The tints under a status chip and a toned card, over a raised card.
    static let chipTint = 0.12, cardTint = 0.08
    /// What's disabled, at this opacity.
    static let disabled = 0.5
    static let blush = Color(hex: Palette.blush)

    // One spacing scale, on a 4 pt grid, so margins can't drift a point or
    // two per view: 2, 4, 8, 16, 24. No arithmetic on them: a value
    // that isn't on the scale is a new token or a mistake. The popover is
    // roomy on purpose (2026-11-15: 420 pt wide, 24 pt sides, 16 pt inside
    // a card, 13 pt text): the room is for air round each thing, not for
    // more things.
    /// A title over its detail; lining loose text up with a card's edge.
    static let hair: CGFloat = 2
    /// An icon to its word; lines in a group.
    static let gapTight: CGFloat = 4
    /// The icon column to its text; between cards; a row's vertical padding.
    static let gapSnug: CGFloat = 8
    /// A card's padding; a row's horizontal padding.
    static let gap: CGFloat = 16
    /// The popover's sides.
    static let gutter: CGFloat = 24
    /// Between sections.
    static let gapSection: CGFloat = 24
    /// The icon column in rows and notices.
    static let iconColumn: CGFloat = 20
    /// The smallest a control is to the pointer.
    static let target: CGFloat = 24
    /// The onboarding window's sides, the same on every act, so Back and
    /// Next stay put from one to the next.
    static let windowGutter: CGFloat = 48

    /// Cards, the terminal, the name field.
    static let cardRadius: CGFloat = 12
    /// Rows, tracks, and every button and field.
    static let wellRadius: CGFloat = 8
    /// Chips and segments.
    static let chipRadius: CGFloat = 6
    /// A session's bar and small decorations.
    static let barRadius: CGFloat = 2

    static let width: CGFloat = 420
}

extension Font {
    /// Rounded for names, titles and numbers: the friendly voice. Body text
    /// stays the system face. Prefer the named styles below.
    static func boop(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // The type scale: eight sizes, by what the text is. Nothing under 10 pt.
    /// The ring's number; onboarding's titles.
    static let boopDisplay = boop(28, .bold)
    /// The buddy's name, a level, a pane's title.
    static let boopTitle = boop(18, .bold)
    /// Onboarding's card and step titles.
    static let boopHeading = boop(15, .bold)
    /// Step numbers; the face legend.
    static let boopLabel = boop(13, .bold)
    /// Onboarding's body lines.
    static let lead = Font.system(size: 14)
    /// Text. A row's title is medium; a card's title is semibold.
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Detail lines; small buttons.
    static let detail = Font.system(size: 12)
    static let detailStrong = Font.system(size: 12, weight: .medium)
    /// Chips, day names, the device line.
    static let chip = Font.system(size: 10, weight: .medium)
    /// What an agent is doing; a file or branch name.
    static let mono = Font.system(size: 12, design: .monospaced)
}

// MARK: - Motion

extension Animation {
    static func boopEase(_ duration: Double = 0.3) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// Tone crossfades and number changes: a soft settle, no bounce.
    static var boopSettle: Animation { boopEase(0.28) }

    /// Something arriving: one gentle overshoot, like the device's cards.
    static var boopPop: Animation { .spring(response: 0.34, dampingFraction: 0.68) }
}

// A plain key: the `@Entry` macro's plugin isn't in Command Line Tools.
private struct StillMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Holds every looping animation still: for snapshots, and while the
    /// popover is closed.
    var stillMotion: Bool {
        get { self[StillMotionKey.self] }
        set { self[StillMotionKey.self] = newValue }
    }
}

// MARK: - Building blocks

/// A card with one soft line: what's not there yet, or why.
struct NoteCard: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Card {
            Text(text).font(.body).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A raised card on the paper: one hairline, one radius, one padding, so the
/// column reads as a stack of the same object.
struct Card<Content: View>: View {
    /// A card of rows, which pad themselves, has none.
    static var rows: CGFloat { 0 }

    var padding: CGFloat = Theme.gap
    var tone: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.map { $0.opacity(Theme.cardTint) } ?? Theme.raised,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(tone?.opacity(0.45) ?? Theme.hairline, lineWidth: 1))
    }
}

/// A labelled section: a small, tracked-out label, then its content. Space
/// and the label separate sections, not rules.
/// A pane's title row: a Back chevron and its title.
struct PaneTitle: View {
    let title: String
    let back: () -> Void

    init(_ title: String, back: @escaping () -> Void) {
        self.title = title
        self.back = back
    }

    var body: some View {
        HStack(spacing: Theme.gapTight) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.quiet)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back")
            Text(title).font(.boop(16)).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter - 8)
        .padding(.top, Theme.gutter - 4)
        .padding(.bottom, Theme.gap)
    }
}

/// One of the memory's recent days: when, and its line.
struct DayRow: View {
    let entry: Runtime.Status.DayLine
    var selectable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.when).font(.chip).foregroundStyle(Theme.inkSoft)
            let line = Text(entry.line).font(.body).fixedSize(horizontal: false, vertical: true)
            if selectable { line.textSelection(.enabled) } else { line }
        }
    }
}

struct PaneSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            SectionLabel(label)
            content
        }
    }
}

/// A section's label: small, tracked-out capitals, lined up with the text
/// in the cards under it.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkSoft)
            .padding(.leading, Theme.gap)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The raw detail under plain words, behind Details, for whoever wants it.
struct MoreDetails: View {
    let text: String
    @ObservedObject private var open = OpenDetails.shared

    init(_ text: String) { self.text = text }

    /// Open or not, by its text, the same in every copy of it: FittedScroll
    /// lays its content out more than once, and a copy's own state would
    /// open the one clicked while the copy that sets the height stayed shut.
    private var shown: Bool { open.texts.contains(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(.boopSettle) { open.toggle(text) } } label: {
                Label("Details", systemImage: shown ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .font(.detailStrong).foregroundStyle(Theme.inkSoft)
            .padding(.top, 2)
            if shown {
                Text(text).caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Which Details are open, by their text, for the app's lifetime.
@MainActor
final class OpenDetails: ObservableObject {
    static let shared = OpenDetails()
    @Published private(set) var texts: Set<String> = []
    /// Opens it, for a snapshot to show.
    func show(_ text: String) { texts.insert(text) }
    func toggle(_ text: String) {
        if texts.remove(text) == nil { texts.insert(text) }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// The hairline between a card's setting rows, from under their icons.
struct RowDivider: View {
    var body: some View {
        Hairline().padding(.leading, Theme.gap + Theme.iconColumn + Theme.gapSnug).padding(.trailing, Theme.gap)
    }
}

extension View {
    /// Small soft text: a caption under or beside what it explains.
    func caption() -> some View {
        font(.detail).foregroundStyle(Theme.inkSoft)
    }
}

extension View {
    /// A plain text field in a box of `fill`, whose edge darkens and
    /// thickens while it has the focus.
    func fieldBox(_ fill: Color, radius: CGFloat, focus: FocusState<Bool>.Binding) -> some View {
        textFieldStyle(.plain)
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(focus.wrappedValue ? Theme.inkSoft : Theme.hairlineStrong, lineWidth: focus.wrappedValue ? 1.5 : 1))
            .focused(focus)
    }
}

/// A status dot. It breathes only while something is live, so motion here
/// always means "happening now".
struct StateDot: View {
    var tone: Color
    var pulsing = false
    @Environment(\.stillMotion) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(tone)
            .frame(width: 7, height: 7)
            .overlay(PulseRing(tone: tone, live: pulsing && !still && !reduceMotion).frame(width: 16, height: 16))
            .accessibilityHidden(true)
    }
}

/// The ring a breathing dot sends out: 2.2 times the dot and gone in 1.6 s,
/// easing out, again and again. Core Animation runs it in the window
/// server, since a SwiftUI animation that repeats forever lays out and
/// draws the whole popover again on every frame of the display.
private struct PulseRing: NSViewRepresentable {
    var tone: Color
    var live: Bool

    func makeNSView(context: Context) -> PulseRingView { PulseRingView() }
    func updateNSView(_ view: PulseRingView, context: Context) { view.set(NSColor(tone), live: live) }
}

final class PulseRingView: NSView {
    static let spread: CGFloat = 2.2, seconds = 1.6, opacity: Float = 0.35
    let ring = CALayer()
    private var colour = NSColor.clear
    private(set) var live = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// The dot's 7 pt, in the middle.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        ring.cornerRadius = 3.5
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func set(_ colour: NSColor, live: Bool) {
        self.colour = colour
        paint()
        guard live != self.live else { return }
        self.live = live
        guard live else {
            ring.removeAnimation(forKey: "breath")
            return
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = Self.spread
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Self.opacity
        fade.toValue = 0
        let breath = CAAnimationGroup()
        breath.animations = [grow, fade]
        breath.duration = Self.seconds
        breath.timingFunction = CAMediaTimingFunction(name: .easeOut)
        breath.repeatCount = .infinity
        breath.isRemovedOnCompletion = false
        ring.add(breath, forKey: "breath")
    }

    /// The tone as this appearance has it: the inks change with it.
    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance { ring.backgroundColor = colour.cgColor }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The one chip: a word, maybe an icon before it, in its tone on a wash of
/// the same hue, or soft ink on the well with no tone. `solid` fills it
/// with the tone instead, for the one thing that must be seen first.
struct Chip: View {
    let text: String
    var icon: String? = nil
    var tone: Color? = nil
    var solid = false

    init(_ text: String, icon: String? = nil, tone: Color? = nil, solid: Bool = false) {
        self.text = text
        self.icon = icon
        self.tone = tone
        self.solid = solid
    }

    var body: some View {
        HStack(spacing: Theme.gapTight) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.chip)
        .foregroundStyle(solid ? Color(hex: "#1C1400") : tone ?? Theme.inkSoft)
        .fixedSize()
        .padding(.horizontal, Theme.gapSnug).padding(.vertical, Theme.gapTight)
        .background(solid ? (tone ?? Theme.amber) : tone?.opacity(Theme.chipTint) ?? Theme.well,
                    in: RoundedRectangle(cornerRadius: Theme.chipRadius))
    }
}

/// Footer and inline buttons: quiet text that darkens on hover, and fades
/// while disabled.
struct QuietButtonStyle: ButtonStyle {
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = enabled && (hovering || configuration.isPressed)
        return configuration.label
            .foregroundStyle(!enabled ? Theme.inkFaint : lit ? Theme.ink : Theme.inkSoft)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.chipRadius)
                .fill(!lit ? .clear : configuration.isPressed ? Theme.hairline : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

/// A card or row that opens its thread: it looks as it did, with a
/// darker edge on hover and a little squash when pressed.
struct OpensButtonStyle: ButtonStyle {
    var radius: CGFloat
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(hovering || configuration.isPressed ? Theme.inkFaint : .clear, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
            .animation(.boopSettle, value: configuration.isPressed)
    }
}

/// A small button for rows: outlined for Remove, Reconnect and Save, filled
/// for Connect and Repair.
struct RowButtonStyle: ButtonStyle {
    var filled = false
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.detailStrong)
            .foregroundStyle(filled ? Theme.fillLabel : Theme.ink)
            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapTight)
            .frame(minHeight: Theme.target)
            .background(RoundedRectangle(cornerRadius: Theme.wellRadius).fill(
                filled ? (pressed ? Theme.fillPressed : Theme.fill) : (hovering || pressed ? Theme.well : Theme.lifted)))
            .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius)
                .strokeBorder(filled ? .clear : Theme.hairlineStrong, lineWidth: 1))
            .opacity(enabled ? 1 : Theme.disabled)
            .contentShape(RoundedRectangle(cornerRadius: Theme.wellRadius))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

/// An on-off switch, drawn here because the system's draws grey in the
/// popover's inactive window, so on looked off: sage when on, as everything
/// on is, a hairline groove when off.
struct SwitchStyle: ToggleStyle {
    /// The track's height; its length is the system switch's proportion of it.
    var height: CGFloat
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(on ? Theme.sageSignal : Theme.controlOff)
                .frame(width: height * 1.75, height: height)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                }
                .opacity(enabled ? 1 : Theme.disabled)
                .animation(.boopSettle, value: on)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // VoiceOver reads it as the switch it is.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A slider in whole steps from 0 to `most`, drawn here for the reason the
/// switch is: the system's draws grey in the popover's inactive window,
/// and its tick under every step crowds a short track. A groove filled in
/// ink up to a white knob, which glides from step to step.
struct StepSlider: View {
    @Binding var value: Int
    let most: Int
    @ViewState private var hovering = false
    @ViewState private var dragging = false
    @Environment(\.isEnabled) private var enabled
    static let knob: CGFloat = 14, groove: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let run = max(1, geo.size.width - Self.knob)
            let x = run * CGFloat(min(max(value, 0), most)) / CGFloat(max(most, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlOff).frame(height: Self.groove)
                Capsule().fill(Theme.ink).frame(width: x + Self.knob / 2, height: Self.groove)
                Circle().fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                    .frame(width: Self.knob, height: Self.knob)
                    .scaleEffect(dragging ? 1.12 : hovering ? 1.06 : 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    dragging = true
                    let step = Int(((drag.location.x - Self.knob / 2) / run * CGFloat(most)).rounded())
                    let next = min(max(step, 0), most)
                    if next != value { value = next }
                }
                .onEnded { _ in dragging = false })
            .animation(.boopSettle, value: value)
            .animation(.boopSettle, value: dragging)
            .animation(.boopSettle, value: hovering)
        }
        .frame(height: Self.knob + 4)
        .opacity(enabled ? 1 : Theme.disabled)
        .onHover { hovering = $0 }
        // VoiceOver and the keyboard's arrows take it as the slider it is.
        .accessibilityRepresentation {
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: 0...Double(most), step: 1)
        }
    }
}

extension ToggleStyle where Self == SwitchStyle {
    /// The popover's switch, about the system's mini one.
    static var boop: SwitchStyle { SwitchStyle(height: 16) }
    /// Onboarding's, about the system's regular one.
    static var boopLarge: SwitchStyle { SwitchStyle(height: 22) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

/// An icon alone that does something: a cross, a pin, a chevron. Small to
/// the eye, a 24 pt square to the pointer.
struct QuietIconButtonStyle: ButtonStyle {
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = enabled && (hovering || configuration.isPressed)
        return configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(!enabled ? Theme.inkFaint : lit ? Theme.ink : Theme.inkSoft)
            .frame(width: Theme.target, height: Theme.target)
            .background(RoundedRectangle(cornerRadius: Theme.chipRadius)
                .fill(!lit ? .clear : configuration.isPressed ? Theme.hairline : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

/// Words that go somewhere: "See everything ›", "Details". Their tone, no
/// box, underlined on hover, a whole target tall.
struct WordLinkStyle: ButtonStyle {
    var tone: Color = Theme.sageInk
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.detailStrong)
            .foregroundStyle(tone)
            .underline(hovering)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: Theme.target)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == QuietIconButtonStyle {
    static var quietIcon: QuietIconButtonStyle { QuietIconButtonStyle() }
}

extension ButtonStyle where Self == WordLinkStyle {
    static var wordLink: WordLinkStyle { WordLinkStyle() }
    static func wordLink(_ tone: Color) -> WordLinkStyle { WordLinkStyle(tone: tone) }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
    static var rowFilled: RowButtonStyle { RowButtonStyle(filled: true) }
}

// MARK: - Hex colours

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
