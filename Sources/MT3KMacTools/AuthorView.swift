import SwiftUI
import AppKit

struct AuthorLinksView: View {
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private struct SocialLink: Identifiable {
        let id = UUID()
        let label: String
        let symbol: String
        let url: String
        let tint: Color
    }

    private let links: [SocialLink] = [
        .init(label: "GitHub",   symbol: "chevron.left.forwardslash.chevron.right",
              url: "https://github.com/MondoBoricua?tab=repositories",
              tint: Color(red: 0.45, green: 0.55, blue: 0.95)),
        .init(label: "YouTube",  symbol: "play.rectangle.fill",
              url: "https://www.youtube.com/@MT3K",
              tint: Color(red: 1.0, green: 0.22, blue: 0.22)),
        .init(label: "LinkedIn", symbol: "briefcase.fill",
              url: "https://www.linkedin.com/in/jdiazpr",
              tint: Color(red: 0.0, green: 0.47, blue: 0.71)),
        .init(label: "X",        symbol: "xmark.circle.fill",
              url: "https://x.com/MondoBoricua",
              tint: Color(red: 0.85, green: 0.85, blue: 0.90)),
        .init(label: "TikTok",   symbol: "music.note",
              url: "https://www.tiktok.com/@MondoBoricua",
              tint: Color(red: 0.93, green: 0.18, blue: 0.50)),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)

            HStack(spacing: 5) {
                Text("Hecho por")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                Text("MT3K")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
            }

            HStack(spacing: 6) {
                ForEach(links) { link in
                    SocialButton(link: link)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.bgCard.opacity(0.6))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    private struct SocialButton: View {
        let link: SocialLink
        @State private var hovering = false

        var body: some View {
            Link(destination: URL(string: link.url)!) {
                Image(systemName: link.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(hovering ? .white : Theme.textSecondary)
                    .background(hovering ? link.tint : Theme.bgDark)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
                    .cornerRadius(6)
                    .scaleEffect(hovering ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .help(link.label)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
