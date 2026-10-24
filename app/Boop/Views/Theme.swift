import AppKit
import SwiftUI

/// The app's palette, the device's "Warm Terminal": warm paper
/// and ink in both appearances, black glass for the face tile and the one
/// filled button (oat on dark paper), and one amber accent, for needs you
/// only. Working and idle are greys, as on the device; sage means connected
/// and on, and clay means trouble. It's hand-set rather than the system's
/// greys, because the popover belongs to an object on your desk. Every
/// `*Ink` tone clears 4.5:1 on its paper, cards, the well and its own chip
/// (`Boop --snapshots` checks); `inkFaint` doesn't and is for decoration and
/// disabled things only.
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
    /// The menu-bar icon's amber on a light menu bar, where the device's is 1.7:1.
    static let menuAmberLight = "#B87400"
    static let sage = "#6E9B5E", sageInkLight = "#466638", sageInkDark = "#A3CC90"
    static let clayInkLight = "#9C3B2E", clayInkDark = "#F09384"

    /// The device's black glass, the oat of its text, and the designs' coral
    /// cheeks (the popover's tile takes the rest of the face's colours from
    /// FaceDesigns). Glass with an oat label is the filled button on light
    /// paper; on dark paper it's the other way round.
    static let glass = "#000000", glassPressed = "#2A2620", oat = "#E8DCC4", oatPressed = "#CFC2A8"
    static let blush = "#F1787D"
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
    static let amberInk = adaptive(Palette.amberInkLight, Palette.amberInkDark)
    static let sage = Color(hex: Palette.sage)
    static let sageInk = adaptive(Palette.sageInkLight, Palette.sageInkDark)
    static let clayInk = adaptive(Palette.clayInkLight, Palette.clayInkDark)
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
    static let blush = Color(hex: Palette.blush)

    // One spacing scale, so margins can't drift a point or two per view.
    static let gutter: CGFloat = 18
    static let gapTight: CGFloat = 4
    static let gapSnug: CGFloat = 8
    static let gap: CGFloat = 12
    static let gapLoose: CGFloat = 18
    static let gapSection: CGFloat = 20
    /// The onboarding window's sides, the same on every act, so Back and
    /// Next stay put from one to the next.
    static let windowGutter: CGFloat = 48

    static let cardRadius: CGFloat = 12
    static let wellRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6

    static let width: CGFloat = 360
}

extension Font {
    /// Rounded for names, titles and numbers: the friendly voice. Body text
    /// stays the system face.
    static func boop(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
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

/// A raised card on the paper: one hairline, one radius, one padding, so the
/// column reads as a stack of the same object.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
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
struct PaneSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// The raw detail under plain words, behind Details, for whoever wants it.
struct MoreDetails: View {
    let text: String
    @ViewState private var shown = false

    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(.boopSettle) { shown.toggle() } } label: {
                Label("Details", systemImage: shown ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            .padding(.top, 2)
            if shown {
                Text(text).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
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
    @ViewState private var up = false
    @Environment(\.stillMotion) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let live = pulsing && !still && !reduceMotion
        Circle()
            .fill(tone)
            .frame(width: 7, height: 7)
            .overlay(Circle().fill(tone).scaleEffect(up ? 2.2 : 1).opacity(up ? 0 : 0.35))
            .animation(live ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : .default, value: up)
            .onAppear { up = live }
            .onChange(of: live) { _, live in up = live }
            .accessibilityHidden(true)
    }
}

/// The status word in its tone, on a wash of the same hue.
struct StatusChip: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tone.opacity(Theme.chipTint), in: RoundedRectangle(cornerRadius: Theme.chipRadius))
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

/// The one filled button per screen: black glass with an oat label, like
/// the device's face (oat on dark paper), rounded, a little squash when
/// pressed.
struct ProminentButtonStyle: ButtonStyle {
    var wide = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.fillLabel)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(configuration.isPressed ? Theme.fillPressed : Theme.fill,
                        in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.boopSettle, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? Theme.fillLabel : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                filled ? (pressed ? Theme.fillPressed : Theme.fill) : (hovering || pressed ? Theme.well : Theme.paper)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(filled ? .clear : Theme.hairlineStrong, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
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
                .fill(on ? Theme.sage : Theme.hairlineStrong)
                .frame(width: height * 1.75, height: height)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                }
                .opacity(enabled ? 1 : 0.4)
                .animation(.boopSettle, value: on)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // VoiceOver reads it as the switch it is.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
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

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
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
