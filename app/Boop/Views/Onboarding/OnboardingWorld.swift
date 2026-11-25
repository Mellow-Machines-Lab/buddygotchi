import BoopKit
import SwiftUI

/// The world's act: it tells, it doesn't ask. Boop lives in a world with
/// everyone else's buddies, on by default; what others see, and what they
/// never do. One button carries on; "Keep Boop private" switches the
/// world off and carries on. Nothing is sent before this act was shown.
struct WorldAct: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ActFrame(kind: .hero, title: "I live in a world of buddies",
                 lead: "Everyone's buddies are in it together. We can wave at each other, and send a boop or a heart.",
                 bar: ActBar(model: model, next: "Sounds good", quiet: ("Keep \(model.name) private", { model.keepPrivate() }))) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero, face: .idle)
        } content: {
            VStack(spacing: Theme.gap) {
                HStack(alignment: .top, spacing: Theme.gap) {
                    side("Others see", icon: "eye", lines: [
                        "My name and level", "Roughly where I am, by time zone", "What I'm doing, in one word",
                        "Counts, like tests passed", "My XP this week, in a league",
                    ])
                    side("Nobody sees", icon: "lock", lines: [
                        "Your name", "Your projects and code", "What you say", "What I remember about you",
                    ])
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("You can change this in Settings any time.")
                    .font(.note).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func side(_ title: String, icon: String, lines: [String]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapTight) {
                Label(title, systemImage: icon).font(.boopHeading)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
    }
}
