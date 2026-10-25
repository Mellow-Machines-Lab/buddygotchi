import BoopKit
import SwiftUI

/// Onboarding's card for the brain's key (Jev's, from TypeSafe), in act 7.
/// It stands alone so that it comes out whole once Boop has a brain of its
/// own: delete this file and the one line in `SmallThingsAct` that shows it.
struct OnboardingBrainKey: View {
    @ObservedObject var app: AppModel
    @ViewState private var key = ""
    @ViewState private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("Give me a brain", systemImage: "sparkles").font(.boop(15, .bold))
                        Spacer()
                        Link(destination: AppModel.jevDocs) {
                            HStack(spacing: 2) {
                                Text("Jev's docs")
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    Text(saved ? "Now I can answer you. Hold my button and ask me “how many agents are running?”"
                         : "A Jev API key lets TypeSafe's AI pick how I react and what mood I'm in. "
                         + "Without one I still show what your agents do and when you're needed.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.gapSnug) {
                    SecureField("Jev API key", text: $key)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .fieldBox(Theme.paper, radius: 7, focus: $focused)
                        .onChange(of: key) { saved = false }
                    if saved {
                        Label("Saved", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.sageInk)
                    } else {
                        Button("Save") {
                            let key = key
                            Task { saved = await app.saveKey(key) }
                        }
                        .buttonStyle(.row)
                        .disabled(key.isEmpty)
                    }
                }
            }
        }
    }
}
