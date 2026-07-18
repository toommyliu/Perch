import Foundation

enum MeetingProvider: String, Codable, Equatable {
    case zoom
    case googleMeet
    case microsoftTeams
    case webex
    case other

    var displayName: String {
        switch self {
        case .zoom:
            return "Zoom"
        case .googleMeet:
            return "Google Meet"
        case .microsoftTeams:
            return "Microsoft Teams"
        case .webex:
            return "Webex"
        case .other:
            return "Meeting"
        }
    }
}

struct MeetingLink: Equatable {
    let url: URL
    let provider: MeetingProvider
}

struct MeetingLinkExtractor {
    private static let meetingContextPriorities = [
        "join": 3,
        "call": 3,
        "conference": 2,
        "meet": 2,
        "video": 2,
        "meeting": 1
    ]

    func meetingLink(from strings: [String?]) -> MeetingLink? {
        let strings = strings.compactMap(\.self)

        // Prefer recognized providers even when a generic link appears first in the notes.
        for string in strings {
            if let link = links(in: string).compactMap({ Self.recognizedLink($0.url) }).first {
                return link
            }
        }

        let contextualLink = strings.enumerated()
            .flatMap { stringIndex, string in
                contextualLinks(in: string, stringIndex: stringIndex)
            }
            .min { Self.isPreferred($0, over: $1) }

        return contextualLink.map {
            MeetingLink(url: $0.url, provider: .other)
        }
    }

    private func links(in string: String) -> [DetectedLink] {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        return detector.matches(in: string, options: [], range: range).compactMap { match in
            guard let url = match.url else { return nil }
            return DetectedLink(url: url, range: match.range)
        }
    }

    private func contextualLinks(in string: String, stringIndex: Int) -> [ContextualLink] {
        let links = links(in: string)
        let contexts = Self.meetingContexts(in: string, excluding: links)

        return links.enumerated().compactMap { linkIndex, link in
            guard Self.isSafeWebURL(link.url) else { return nil }

            var bestContext: (priority: Int, distance: Int)?
            for context in contexts {
                let distance = Self.distance(between: context.range, and: link.range)

                if let currentBest = bestContext {
                    if context.priority > currentBest.priority
                        || (context.priority == currentBest.priority && distance < currentBest.distance)
                    {
                        bestContext = (context.priority, distance)
                    }
                } else {
                    bestContext = (context.priority, distance)
                }
            }

            guard let bestContext else { return nil }
            return ContextualLink(
                url: link.url,
                contextPriority: bestContext.priority,
                contextDistance: bestContext.distance,
                stringIndex: stringIndex,
                linkIndex: linkIndex
            )
        }
    }

    private static func recognizedLink(_ url: URL) -> MeetingLink? {
        if ZoomMeetingLaunchURLBuilder.isZoomMeetingURL(url) {
            return MeetingLink(url: url, provider: .zoom)
        }

        guard isSafeWebURL(url), let host = url.host?.lowercased() else {
            return nil
        }

        if host == "meet.google.com", !url.path.isEmpty, url.path != "/" {
            return MeetingLink(url: url, provider: .googleMeet)
        }

        if (host == "teams.microsoft.com" && url.path.lowercased().contains("meetup-join"))
            || host == "teams.live.com"
        {
            return MeetingLink(url: url, provider: .microsoftTeams)
        }

        if host == "webex.com" || host.hasSuffix(".webex.com") {
            return MeetingLink(url: url, provider: .webex)
        }

        return nil
    }

    private static func meetingContexts(
        in string: String,
        excluding links: [DetectedLink]
    ) -> [MeetingContext] {
        var contexts: [MeetingContext] = []
        string.enumerateSubstrings(
            in: string.startIndex..<string.endIndex,
            options: .byWords
        ) { substring, substringRange, _, _ in
            guard let substring,
                  let priority = meetingContextPriorities[substring.lowercased()]
            else {
                return
            }

            let range = NSRange(substringRange, in: string)
            guard !links.contains(where: {
                NSIntersectionRange(range, $0.range).length > 0
            }) else {
                return
            }

            contexts.append(MeetingContext(range: range, priority: priority))
        }
        return contexts
    }

    private static func distance(between lhs: NSRange, and rhs: NSRange) -> Int {
        if NSMaxRange(lhs) <= rhs.location {
            return rhs.location - NSMaxRange(lhs)
        }
        if NSMaxRange(rhs) <= lhs.location {
            return lhs.location - NSMaxRange(rhs)
        }
        return 0
    }

    private static func isPreferred(_ lhs: ContextualLink, over rhs: ContextualLink) -> Bool {
        if lhs.contextPriority != rhs.contextPriority {
            return lhs.contextPriority > rhs.contextPriority
        }
        if lhs.contextDistance != rhs.contextDistance {
            return lhs.contextDistance < rhs.contextDistance
        }
        if lhs.stringIndex != rhs.stringIndex {
            return lhs.stringIndex < rhs.stringIndex
        }
        return lhs.linkIndex < rhs.linkIndex
    }

    private static func isSafeWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return (scheme == "https" || scheme == "http") && url.host != nil
    }
}

private struct DetectedLink {
    let url: URL
    let range: NSRange
}

private struct MeetingContext {
    let range: NSRange
    let priority: Int
}

private struct ContextualLink {
    let url: URL
    let contextPriority: Int
    let contextDistance: Int
    let stringIndex: Int
    let linkIndex: Int
}

struct MeetingLaunchURLBuilder {
    private let zoomBuilder = ZoomMeetingLaunchURLBuilder()

    func launchURL(for link: MeetingLink) -> URL {
        link.provider == .zoom ? zoomBuilder.launchURL(for: link.url) : link.url
    }
}

struct ZoomMeetingLaunchURLBuilder {
    func launchURL(for meetingURL: URL) -> URL {
        if Self.isNativeZoomURL(meetingURL) {
            return meetingURL
        }

        return nativeJoinURL(for: meetingURL) ?? meetingURL
    }

    static func isZoomMeetingURL(_ url: URL) -> Bool {
        isNativeZoomURL(url) || (isWebZoomURL(url) && meetingIdentifier(from: url) != nil)
    }

    private func nativeJoinURL(for meetingURL: URL) -> URL? {
        guard Self.isWebZoomURL(meetingURL),
              let host = meetingURL.host?.lowercased(),
              let meetingIdentifier = Self.meetingIdentifier(from: meetingURL)
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"

        // Zoom's native URL scheme requires confno to be a numeric meeting ID.
        // Personal meeting room vanity names (/my/<name>) must fall back to the web URL.
        guard meetingIdentifier.allSatisfy(\.isNumber) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: meetingIdentifier)
        ]

        if let password = Self.queryValue(named: "pwd", in: meetingURL) {
            queryItems.append(URLQueryItem(name: "pwd", value: password))
        }

        components.queryItems = queryItems
        return components.url
    }

    private static func isNativeZoomURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "zoommtg" || scheme == "zoomus"
    }

    private static func isWebZoomURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }

        return host == "zoom.us" || host.hasSuffix(".zoom.us")
    }

    private static func meetingIdentifier(from url: URL) -> String? {
        let pathSegments = url.path.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            String(segment).removingPercentEncoding ?? String(segment)
        }

        for (index, segment) in pathSegments.enumerated() {
            let normalizedSegment = segment.lowercased()
            guard normalizedSegment == "j" || normalizedSegment == "w" || normalizedSegment == "my" else {
                continue
            }

            let nextIndex = index + 1
            guard pathSegments.indices.contains(nextIndex), !pathSegments[nextIndex].isEmpty else {
                continue
            }

            return pathSegments[nextIndex]
        }

        return nil
    }

    private static func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { item in
            item.name.lowercased() == name.lowercased()
        }?.value
    }
}
