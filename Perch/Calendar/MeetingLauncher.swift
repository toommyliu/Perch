import AppKit

@MainActor
struct MeetingLauncher {
    private let launchURLBuilder: MeetingLaunchURLBuilder
    private let openURL: (URL) -> Bool

    init(
        launchURLBuilder: MeetingLaunchURLBuilder = MeetingLaunchURLBuilder(),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.launchURLBuilder = launchURLBuilder
        self.openURL = openURL
    }

    @discardableResult
    func open(_ link: MeetingLink) -> Bool {
        let preferredURL = launchURLBuilder.launchURL(for: link)
        if openURL(preferredURL) {
            return true
        }

        if preferredURL != link.url, openURL(link.url) {
            return true
        }

        PerchLog.actions.error(
            """
            Meeting launch failed: \
            provider=\(link.provider.rawValue, privacy: .public) \
            scheme=\(preferredURL.scheme ?? "none", privacy: .public)
            """
        )
        return false
    }
}
