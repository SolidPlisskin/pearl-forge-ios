import SwiftUI

/// Saved recordings: original audio, both transcripts, and the audio in your
/// voice. Placeholder until the history screen is built.
struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No recordings yet", systemImage: "clock")
            } description: {
                Text("Every thought you refine is saved here with the original recording and both transcripts.")
            }
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
