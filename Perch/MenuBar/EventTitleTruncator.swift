import Foundation

enum EventTitleTruncator {
    static func truncate(_ title: String, maxLength: Int) -> String {
        guard maxLength > 3, title.count > maxLength else {
            return title
        }

        let endIndex = title.index(title.startIndex, offsetBy: maxLength - 3)
        return "\(title[..<endIndex])..."
    }
}
