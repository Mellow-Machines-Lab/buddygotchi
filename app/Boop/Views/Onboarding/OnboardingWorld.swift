import BoopKit
import SwiftUI

/// The world's act: it tells, it doesn't ask. Boop lives in a world with
/// everyone else's buddies, on by default; what others see, and what they
/// never do. One button carries on; "Keep Boop private" switches the
/// world off and carries on. Nothing is sent before this act was shown.
struct WorldAct: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 14) {
            OnboardingBuddy(model: model, snapshot: .onboarding(mood: "excited"), size: 96, face: .happy)
            ActTitle(title: "I live in a world of buddies",
                     detail: "Everyone's buddies are in it together. We can wave at each other, and send a boop or a heart.")
            HStack(alignment: .top, spacing: 12) {
                side("Others see", icon: "eye", lines: [
                    "My name and level", "Roughly where I am, by time zone", "What I'm doing, in one word",
                    "Counts, like tests passed",
                ])
                side("Nobody sees", icon: "lock", lines: [
                    "Your name", "Your projects and code", "What you say", "What I remember about you",
                ])
            }
            .frame(maxWidth: 520)
            Text("You can change this in Settings any time.")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
            ActNav(model: model, next: "Sounds good",
                   quiet: ("Keep \(model.name) private", { model.keepPrivate() }))
        }
    }

    private func side(_ title: String, icon: String, lines: [String]) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.boop(15, .bold))
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
