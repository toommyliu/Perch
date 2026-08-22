import Foundation

struct MenuBarLabelWidthLimiter {
    private static let leadingShare = 0.65
    private static let minimumCharactersForMiddleEllipsis = 10

    /// Fits a single-line agenda label while preserving its relative-time text.
    static func fit(
        title: String,
        relativeText: String,
        leadingText: String,
        maximumWidth: CGFloat,
        measure: (String) -> CGFloat
    ) -> String {
        let title = normalized(title)
        let timeOnlyLabel = "\(leadingText)\(relativeText)"
        guard !title.isEmpty else { return timeOnlyLabel }

        let fullLabel = label(
            title: title,
            relativeText: relativeText,
            leadingText: leadingText
        )
        guard measure(fullLabel) > maximumWidth else { return fullLabel }

        let characters = Array(title)
        let maximumRetainedCount = max(0, characters.count - 1)
        let ellipsisOnlyLabel = truncatedLabel(
            characters: characters,
            retainedCount: 0,
            relativeText: relativeText,
            leadingText: leadingText,
            style: .middle
        )
        guard measure(ellipsisOnlyLabel) <= maximumWidth else { return timeOnlyLabel }

        let middleRetainedCount = largestRetainedCount(
            upTo: maximumRetainedCount,
            maximumWidth: maximumWidth,
            measure: measure
        ) { retainedCount in
            truncatedLabel(
                characters: characters,
                retainedCount: retainedCount,
                relativeText: relativeText,
                leadingText: leadingText,
                style: .middle
            )
        }

        if middleRetainedCount < minimumCharactersForMiddleEllipsis {
            let tailRetainedCount = largestRetainedCount(
                upTo: maximumRetainedCount,
                maximumWidth: maximumWidth,
                measure: measure
            ) { retainedCount in
                truncatedLabel(
                    characters: characters,
                    retainedCount: retainedCount,
                    relativeText: relativeText,
                    leadingText: leadingText,
                    style: .tail
                )
            }
            return truncatedLabel(
                characters: characters,
                retainedCount: tailRetainedCount,
                relativeText: relativeText,
                leadingText: leadingText,
                style: .tail
            )
        }

        return truncatedLabel(
            characters: characters,
            retainedCount: middleRetainedCount,
            relativeText: relativeText,
            leadingText: leadingText,
            style: .middle
        )
    }

    private static func largestRetainedCount(
        upTo maximumCount: Int,
        maximumWidth: CGFloat,
        measure: (String) -> CGFloat,
        candidate: (Int) -> String
    ) -> Int {
        var lowerBound = 0
        var upperBound = maximumCount

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound + 1) / 2
            if measure(candidate(midpoint)) <= maximumWidth {
                lowerBound = midpoint
            } else {
                upperBound = midpoint - 1
            }
        }

        while lowerBound > 0, measure(candidate(lowerBound)) > maximumWidth {
            lowerBound -= 1
        }
        return lowerBound
    }

    private static func truncatedLabel(
        characters: [Character],
        retainedCount: Int,
        relativeText: String,
        leadingText: String,
        style: EllipsisStyle
    ) -> String {
        let truncatedTitle: String
        switch style {
        case .middle:
            let leadingCount = Int(ceil(Double(retainedCount) * leadingShare))
            let trailingCount = retainedCount - leadingCount
            let leading = String(characters.prefix(leadingCount))
                .trimmingCharacters(in: .whitespaces)
            let trailing = String(characters.suffix(trailingCount))
                .trimmingCharacters(in: .whitespaces)
            truncatedTitle = "\(leading)…\(trailing)"
        case .tail:
            let leading = String(characters.prefix(retainedCount))
                .trimmingCharacters(in: .whitespaces)
            truncatedTitle = "\(leading)…"
        }

        return label(
            title: truncatedTitle,
            relativeText: relativeText,
            leadingText: leadingText
        )
    }

    private static func label(
        title: String,
        relativeText: String,
        leadingText: String
    ) -> String {
        "\(leadingText)\(title) · \(relativeText)"
    }

    private static func normalized(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private enum EllipsisStyle {
    case middle
    case tail
}
