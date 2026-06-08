import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 90, height: 64)
                VStack(alignment: .leading) {
                    Text("StayHere")
                        .font(.largeTitle.bold())
                    Text("macOS Spaces, named and tamed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .font(.headline)
                Text("Protect your focus by keeping different contexts in separate Spaces.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("What it does")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Name your Spaces for instant orientation", systemImage: "tag")
                    Label("Stay on the Space you chose when clicking Dock icons", systemImage: "arrow.right.circle")
                    Label("Quick space switching with configurable shortcuts", systemImage: "keyboard")
                    Label("Window switcher shows only windows on the current Space", systemImage: "macwindow")
                    Label("Subtle HUD confirms space changes", systemImage: "rectangle.on.rectangle")
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("© 2026 Tomasz Habiger. Licensed under PolyForm Noncommercial License.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Source code available on GitHub: https://github.com/thabiger/stay-here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        NSWorkspace.shared.open(URL(string: "https://github.com/thabiger/stay-here")!)
                    }
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 520)
    }
}
