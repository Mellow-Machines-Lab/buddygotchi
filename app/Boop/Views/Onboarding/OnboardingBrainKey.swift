import BoopKit
import SwiftUI

/// Onboarding's card for the brain's key (Jev's, from TypeSafe), in act 7.
/// It stands alone so that it comes out whole once Boop has a brain of its
/// own: delete this file and the one line in `SmallThingsAct` that shows it.
struct OnboardingBrainKey: View {
    @ObservedObject var app: AppModel
    /// Whether a board is here, whose button you hold to talk; with none,
    /// the menu's Talk.
    var hasBoard = true
    @ViewState private var key = ""
    @ViewState private var saved = false
    @ViewState private var failed = false
    @FocusState private var focused: Bool

    /// `saved`: how the last save went, to show it again (true kept, false
    /// refused); nil, none yet.
    init(app: AppModel, hasBoard: Bool = true, saved: Bool? = nil) {
        self.app = app
        self.hasBoard = hasBoard
        _saved = ViewState(initialValue: saved == true)
        _failed = ViewState(initialValue: saved == false)
    }

    var body: some View {
        Card(padding: Theme.gutter) {
            VStack(alignment: .leading, spacing: Theme.gap) {
                VStack(alignment: .leading, spacing: Theme.hair) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Give me a brain", systemImage: "sparkles").font(.boopHeading)
                        Spacer()
                        Link(destination: AppModel.jevDocs) {
                            HStack(spacing: Theme.hair) {
                                Text("Jev's docs")
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .font(.body).foregroundStyle(Theme.inkSoft)
                    }
                    Text(saved ? "Now I can answer you. \(hasBoard ? "Hold my button" : "Click Talk in my menu") and ask me “how many agents are running?”"
                         : failed ? "I couldn't keep that key in your Keychain. Try again, or check Keychain Access."
                         : "A Jev API key lets TypeSafe's AI pick how I react and what mood I'm in. "
                         + "Without one I still show what your agents do and when you're needed.")
                        .font(.body).foregroundStyle(failed && !saved ? Theme.clayInk : Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.gap) {
                    SecureField("Jev API key", text: $key)
                        .font(.note)
                        .padding(.horizontal, Theme.gapSnug)
                        .frame(height: ActSize.control)
                        .fieldBox(Theme.paper, radius: Theme.wellRadius, focus: $focused)
                        .onChange(of: key) {
                            saved = false
                            failed = false
                        }
                        // Return saves the key, rather than leaving the act
                        // with it unsaved.
                        .onSubmit(save)
                    Group {
                        if saved {
                            Label("Saved", systemImage: "checkmark")
                                .font(.bodyMedium).foregroundStyle(Theme.sageInk)
                        } else {
                            Button("Save", action: save)
                                .buttonStyle(ActControlStyle())
                                .disabled(Keychain.cleaned(key).isEmpty)
                        }
                    }
                    .frame(width: ActSize.controls, height: ActSize.control)
                }
            }
        }
    }

    private func save() {
        let key = Keychain.cleaned(key)
        guard !key.isEmpty else { return }
        Task {
            saved = await app.saveKey(key)
            failed = !saved
        }
    }
}
