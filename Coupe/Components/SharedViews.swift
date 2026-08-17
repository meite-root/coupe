import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct MediaArtwork: View {
    let project: MediaProject, store: ManagedMediaStore
    var body: some View {
        Group {
            if let relative = project.thumbnailRelativePath,
               let image = UIImage(contentsOfFile: store.url(for: relative).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: project.mediaKind == .video ? "film" : "waveform")
                    .font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 58).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 10)).clipped()
        .accessibilityHidden(true)
    }
}

extension ClipExportState {
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self { case .pending: "clock"; case .exporting: "arrow.triangle.2.circlepath"; case .ready: "checkmark.circle.fill"; case .failed: "exclamationmark.triangle.fill" }
    }
}
