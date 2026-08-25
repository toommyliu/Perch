import AppKit

@MainActor
struct MeetingLauncher {
    private let launchURLBuilder = MeetingLaunchURLBuilder()

    func open(_ link: MeetingLink) {
        let url = launchURLBuilder.launchURL(for: link)
        guard NSWorkspace.shared.open(url) else {
            PerchLog.actions.error(
                """
                Meeting launch failed: \
                provider=\(link.provider.rawValue, privacy: .public) \
                scheme=\(url.scheme ?? "none", privacy: .public)
                """
            )
            return
        }
    }
}
