import Foundation

enum DateFormatting {
    static func eventTime(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
        )
    }

    static func menuSectionTitle(
        for date: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return relativeDayTitle(dayOffset: 0, locale: locale)
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return relativeDayTitle(dayOffset: 1, locale: locale)
        }

        return date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
        )
    }

    static func weekday(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .weekday(.abbreviated)
        )
    }

    private static func relativeDayTitle(dayOffset: Int, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: dayOffset))
    }
}
