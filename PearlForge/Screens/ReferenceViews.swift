import SafariServices
import SwiftUI

/// A web page to show in the in-app browser.
struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Safari inside the app, so reading a reference doesn't leave Pearl Forge.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// One reference: what kind it is, its title and source, and how it relates.
/// Uses fixed label colours so it reads as text even inside a button.
struct ReferenceRow: View {
    let reference: Reference
    /// The recording it was found for, when shown outside that recording.
    var fromTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(reference.kind.title, systemImage: reference.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(reference.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(3)
            Text(sourceLine)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
            if !reference.note.isEmpty {
                Text(reference.note)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(4)
            }
            if let fromTitle {
                Label(fromTitle, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .multilineTextAlignment(.leading)
    }

    private var sourceLine: String {
        [reference.authors, reference.source.isEmpty ? nil : reference.source, reference.year]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// A recording's topics as small capsules that wrap onto new lines.
struct TopicChips: View {
    let topics: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(topics, id: \.self) { topic in
                Text(topic)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// Lays views out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
