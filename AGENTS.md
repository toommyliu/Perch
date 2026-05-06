# AGENTS.md

## Project Snapshot

Perch is a native macOS menu bar app for showing upcoming Apple Calendar events through EventKit. The app is currently in very early development, with the first implementation focused on creating a read-only, AppKit-first experience that reliably displays calendar events in the menu bar.

## Core Priorities

1. Reliability first.
2. Performance first.
3. Keep behavior predictable across permission changes, calendar database updates, clock/date changes, wake from sleep, and app restarts.

If a tradeoff is required, choose correctness and robustness over short-term convenience.

## Maintainability

Long-term maintainability is a core priority. Keep pure formatting, grouping, settings, and provider logic separated so it can be tested without launching the app.

Prefer small app-internal interfaces over coupling UI code directly to EventKit. Duplicate logic across menu bar label formatting, dropdown construction, and settings persistence is a code smell and should be avoided.

Do not take shortcuts by adding local one-off logic when shared pure logic would make behavior easier to test and reason about.

## References

- EventKit full access: https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29
- EventKit access changes: https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos
- Full access plist key: https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription
- Calendar sandbox entitlement: https://developer.apple.com/documentation/bundleresources/security-entitlements
