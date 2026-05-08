import Foundation

struct ZoomMeetingLinkExtractor {
    func meetingURL(from strings: [String?]) -> URL? {
        for string in strings.compactMap(\.self) {
            if let url = meetingURL(from: string) {
                return url
            }
        }

        return nil
    }

    private func meetingURL(from string: String) -> URL? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        for match in detector.matches(in: string, options: [], range: range) {
            guard let url = match.url,
                  ZoomMeetingLaunchURLBuilder.isZoomMeetingURL(url)
            else {
                continue
            }

            return url
        }

        return nil
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
