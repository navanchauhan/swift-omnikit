import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct JeffDAVClient {
    struct Account: Sendable {
        var accountID: String
        var email: String
        var username: String
        var password: String
        var caldavBaseURL: URL?
        var carddavBaseURL: URL?
        var webdavBaseURL: URL?
        var defaultCalendarURLs: [URL]

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "email": email,
                "caldav_base_url": caldavBaseURL?.absoluteString ?? NSNull(),
                "carddav_base_url": carddavBaseURL?.absoluteString ?? NSNull(),
                "webdav_base_url": webdavBaseURL?.absoluteString ?? NSNull(),
                "default_calendar_urls": defaultCalendarURLs.map(\.absoluteString),
                "capabilities": [
                    "calendar": caldavBaseURL != nil || !defaultCalendarURLs.isEmpty,
                    "contacts": carddavBaseURL != nil,
                    "webdav_notes": webdavBaseURL != nil,
                ],
            ]
        }
    }

    struct CalendarCollection: Sendable {
        var accountID: String
        var name: String
        var url: URL

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "name": name,
                "url": url.absoluteString,
            ]
        }
    }

    struct CalendarEvent: Sendable {
        var accountID: String
        var calendarName: String
        var eventURL: String?
        var uid: String?
        var summary: String?
        var start: String?
        var end: String?
        var location: String?
        var description: String?

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "calendar": calendarName,
                "event_url": eventURL ?? NSNull(),
                "uid": uid ?? NSNull(),
                "summary": summary ?? NSNull(),
                "start": start ?? NSNull(),
                "end": end ?? NSNull(),
                "location": location ?? NSNull(),
                "description": description ?? NSNull(),
            ]
        }
    }

    struct FreeTimeSlot: Sendable {
        var start: Date
        var end: Date
        var timezoneIdentifier: String

        func json() -> [String: Any] {
            let timezone = TimeZone(identifier: timezoneIdentifier) ?? .current
            return [
                "start": isoString(start),
                "end": isoString(end),
                "local_start": localDisplayString(start, timezone: timezone),
                "local_end": localDisplayString(end, timezone: timezone),
                "timezone": timezoneIdentifier,
                "duration_minutes": Int(end.timeIntervalSince(start) / 60),
            ]
        }
    }

    private struct BusyInterval: Sendable {
        var start: Date
        var end: Date
        var summary: String?
        var accountID: String
        var calendarName: String
    }

    struct ToolErrorResult: Sendable {
        var target: String
        var error: String

        func json() -> [String: String] {
            ["target": target, "error": error]
        }
    }

    struct CalendarListAccountResult: Sendable {
        var accountID: String
        var calendars: [CalendarCollection]
        var error: String?

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "calendars": calendars.map { $0.json() },
                "error": error ?? NSNull(),
            ]
        }
    }

    struct CalendarEventsAccountResult: Sendable {
        var accountID: String
        var events: [CalendarEvent]
        var errors: [ToolErrorResult]
        var error: String?

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "events": events.map { $0.json() },
                "errors": errors.map { $0.json() },
                "error": error ?? NSNull(),
            ]
        }
    }

    struct Contact: Sendable {
        var accountID: String
        var sourceURL: String?
        var fullName: String?
        var emails: [String]
        var phones: [String]
        var organization: String?
        var title: String?

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "source_url": sourceURL ?? NSNull(),
                "full_name": fullName ?? NSNull(),
                "emails": emails,
                "phones": phones,
                "organization": organization ?? NSNull(),
                "title": title ?? NSNull(),
            ]
        }
    }

    struct ContactsAccountResult: Sendable {
        var accountID: String
        var contacts: [Contact]
        var errors: [ToolErrorResult]
        var error: String?

        func json() -> [String: Any] {
            [
                "account_id": accountID,
                "contacts": contacts.map { $0.json() },
                "errors": errors.map { $0.json() },
                "error": error ?? NSNull(),
            ]
        }
    }

    static func listAccounts() -> [String: Any] {
        [
            "accounts": loadAccounts().map { $0.json() },
        ]
    }

    static func listCalendars(accountID: String?) async -> [String: Any] {
        let accounts = resolveAccounts(accountID: accountID)
        let results = await withTaskGroup(of: CalendarListAccountResult.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let calendars = try await calendarCollections(account: account)
                        return CalendarListAccountResult(accountID: account.accountID, calendars: calendars, error: nil)
                    } catch {
                        return CalendarListAccountResult(accountID: account.accountID, calendars: [], error: String(describing: error))
                    }
                }
            }
            var output: [CalendarListAccountResult] = []
            for await result in group {
                output.append(result)
            }
            return output.sorted { $0.accountID < $1.accountID }
        }
        return ["accounts": results.map { $0.json() }]
    }

    static func listEvents(
        accountID: String?,
        calendarURL: String?,
        daysBack: Int,
        daysForward: Int,
        limit: Int
    ) async -> [String: Any] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(0, daysBack), to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: max(1, min(daysForward, 90)), to: now) ?? now
        let accounts = resolveAccounts(accountID: accountID)
        let maxEvents = max(1, min(limit, 100))

        let results = await withTaskGroup(of: CalendarEventsAccountResult.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let collections: [CalendarCollection]
                        if let calendarURL, let url = URL(string: calendarURL) {
                            collections = [CalendarCollection(accountID: account.accountID, name: calendarURL, url: url)]
                        } else {
                            collections = try await calendarCollections(account: account)
                        }
                        var events: [CalendarEvent] = []
                        var errors: [ToolErrorResult] = []
                        for collection in collections.prefix(6) {
                            do {
                                events.append(contentsOf: try await queryEvents(account: account, collection: collection, start: start, end: end))
                            } catch {
                                errors.append(ToolErrorResult(target: collection.url.absoluteString, error: String(describing: error)))
                            }
                        }
                        let sorted = events.sorted { ($0.start ?? "") < ($1.start ?? "") }.prefix(maxEvents)
                        return CalendarEventsAccountResult(accountID: account.accountID, events: Array(sorted), errors: errors, error: nil)
                    } catch {
                        return CalendarEventsAccountResult(accountID: account.accountID, events: [], errors: [], error: String(describing: error))
                    }
                }
            }
            var output: [CalendarEventsAccountResult] = []
            for await result in group {
                output.append(result)
            }
            return output.sorted { $0.accountID < $1.accountID }
        }
        return [
            "window": [
                "start": isoString(start),
                "end": isoString(end),
            ],
            "accounts": results.map { $0.json() },
        ]
    }

    static func findFreeTime(
        accountID: String?,
        calendarURL: String?,
        windowStart: String,
        windowEnd: String,
        durationMinutes: Int,
        timezoneIdentifier: String?,
        dayStartHour: Int,
        dayEndHour: Int,
        limit: Int
    ) async -> [String: Any] {
        let timezone = timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        do {
            let start = try parseDate(windowStart)
            let end = try parseDate(windowEnd)
            guard start < end else {
                throw DAVError.invalidDate("window_start must be before window_end")
            }

            let accounts = resolveAccounts(accountID: accountID)
            let busy = await busyIntervals(
                accounts: accounts,
                calendarURL: calendarURL,
                start: start,
                end: end,
                timezone: timezone
            )
            let slots = freeTimeSlots(
                windowStart: start,
                windowEnd: end,
                busyIntervals: busy.intervals,
                durationMinutes: max(5, min(durationMinutes, 24 * 60)),
                timezone: timezone,
                dayStartHour: max(0, min(dayStartHour, 23)),
                dayEndHour: max(1, min(dayEndHour, 24)),
                limit: max(1, min(limit, 50))
            )
            return [
                "window": [
                    "start": isoString(start),
                    "end": isoString(end),
                    "timezone": timezone.identifier,
                ],
                "duration_minutes": max(5, min(durationMinutes, 24 * 60)),
                "working_hours": [
                    "start_hour": max(0, min(dayStartHour, 23)),
                    "end_hour": max(1, min(dayEndHour, 24)),
                ],
                "slots": slots.map { $0.json() },
                "busy_count": busy.intervals.count,
                "errors": busy.errors.map { $0.json() },
            ]
        } catch {
            return [
                "window": [
                    "start": windowStart,
                    "end": windowEnd,
                    "timezone": timezone.identifier,
                ],
                "slots": [],
                "errors": [
                    ["target": accountID ?? "calendar", "error": String(describing: error)],
                ],
            ]
        }
    }

    static func createEvent(
        accountID: String?,
        calendarURL: String?,
        title: String,
        start: String,
        end: String,
        location: String?,
        notes: String?
    ) async throws -> [String: Any] {
        guard let account = resolveAccounts(accountID: accountID).first else {
            throw DAVError.noDAVAccount(accountID ?? "default")
        }
        let collectionURL: URL
        if let calendarURL, let url = URL(string: calendarURL) {
            collectionURL = url
        } else if let first = try await calendarCollections(account: account).first {
            collectionURL = first.url
        } else {
            throw DAVError.noCalendarCollection(account.accountID)
        }
        let startDate = try parseDate(start)
        let endDate = try parseDate(end)
        let uid = "\(UUID().uuidString)@jeff.local"
        let eventURL = collectionURL.appendingPathComponent("\(uid).ics")
        let ics = buildICS(uid: uid, title: title, start: startDate, end: endDate, location: location, notes: notes)
        let response = try await request(account: account, url: eventURL, method: "PUT", contentType: "text/calendar; charset=utf-8", body: ics)
        guard [200, 201, 204].contains(response.statusCode) else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return [
            "status": "created",
            "account_id": account.accountID,
            "event_url": eventURL.absoluteString,
            "uid": uid,
            "title": title,
            "start": isoString(startDate),
            "end": isoString(endDate),
        ]
    }

    static func deleteEvent(accountID: String?, eventURL: String) async throws -> [String: Any] {
        guard let account = resolveAccounts(accountID: accountID).first else {
            throw DAVError.noDAVAccount(accountID ?? "default")
        }
        guard let url = URL(string: eventURL) else {
            throw DAVError.invalidURL(eventURL)
        }
        let response = try await request(account: account, url: url, method: "DELETE", body: nil)
        guard [200, 202, 204, 404].contains(response.statusCode) else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return [
            "status": response.statusCode == 404 ? "already_missing" : "deleted",
            "account_id": account.accountID,
            "event_url": eventURL,
        ]
    }

    static func searchContacts(accountID: String?, addressbookURL: String?, query: String, limit: Int) async -> [String: Any] {
        let accounts = resolveAccounts(accountID: accountID)
        let maxContacts = max(1, min(limit, 50))
        let results = await withTaskGroup(of: ContactsAccountResult.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let addressbooks: [URL]
                        if let addressbookURL, let url = URL(string: addressbookURL) {
                            addressbooks = [url]
                        } else {
                            addressbooks = try await discoverAddressbooks(account: account)
                        }
                        var contacts: [Contact] = []
                        var errors: [ToolErrorResult] = []
                        for addressbook in addressbooks.prefix(4) {
                            do {
                                contacts.append(contentsOf: try await queryContacts(account: account, addressbook: addressbook, query: query, limit: maxContacts))
                            } catch {
                                errors.append(ToolErrorResult(target: addressbook.absoluteString, error: String(describing: error)))
                            }
                        }
                        return ContactsAccountResult(accountID: account.accountID, contacts: Array(contacts.prefix(maxContacts)), errors: errors, error: nil)
                    } catch {
                        return ContactsAccountResult(accountID: account.accountID, contacts: [], errors: [], error: String(describing: error))
                    }
                }
            }
            var output: [ContactsAccountResult] = []
            for await result in group {
                output.append(result)
            }
            return output.sorted { $0.accountID < $1.accountID }
        }
        return [
            "query": query,
            "accounts": results.map { $0.json() },
        ]
    }

    static func listFiles(accountID: String?, path: String?, limit: Int) async throws -> [String: Any] {
        guard let account = resolveAccounts(accountID: accountID).first else {
            throw DAVError.noDAVAccount(accountID ?? "default")
        }
        guard let base = account.webdavBaseURL else {
            throw DAVError.unsupportedCapability(account.accountID, "webdav")
        }
        let url = appendPath(path, to: base)
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop><D:displayname/><D:getcontentlength/><D:getcontenttype/><D:getlastmodified/><D:resourcetype/></D:prop>
        </D:propfind>
        """
        let response = try await request(account: account, url: url, method: "PROPFIND", depth: "1", contentType: "application/xml; charset=utf-8", body: body)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        let files = splitResponses(response.body).dropFirst().prefix(max(1, min(limit, 100))).map { block -> [String: Any] in
            [
                "href": resolveURL(extractFirst("href", from: block) ?? "", relativeTo: url)?.absoluteString ?? NSNull(),
                "display_name": xmlText("displayname", in: block) ?? NSNull(),
                "content_type": xmlText("getcontenttype", in: block) ?? NSNull(),
                "content_length": xmlText("getcontentlength", in: block) ?? NSNull(),
                "last_modified": xmlText("getlastmodified", in: block) ?? NSNull(),
                "is_collection": block.range(of: #"<[^>]*:?collection[\s/>]"#, options: [.regularExpression, .caseInsensitive]) != nil,
            ]
        }
        return [
            "account_id": account.accountID,
            "base_url": base.absoluteString,
            "path": path ?? "",
            "files": Array(files),
        ]
    }

    static func putTextFile(accountID: String?, path: String, text: String, contentType: String) async throws -> [String: Any] {
        guard let account = resolveAccounts(accountID: accountID).first else {
            throw DAVError.noDAVAccount(accountID ?? "default")
        }
        guard let base = account.webdavBaseURL else {
            throw DAVError.unsupportedCapability(account.accountID, "webdav")
        }
        let url = appendPath(path, to: base)
        let response = try await request(account: account, url: url, method: "PUT", contentType: contentType, body: text)
        guard [200, 201, 204].contains(response.statusCode) else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return [
            "status": response.statusCode == 201 ? "created" : "saved",
            "account_id": account.accountID,
            "url": url.absoluteString,
            "byte_count": text.data(using: .utf8)?.count ?? 0,
        ]
    }

    static func loadAccounts() -> [Account] {
        let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }
        return JeffEmailClient.Config.loadAccounts().map { emailConfig in
            let prefix = emailConfig.accountID == "jeff" ? "EMAIL_" : "EMAIL_ACCOUNT_\(emailConfig.accountID.uppercased())_"
            let caldavBase = optionalURL("\(prefix)CALDAV_BASE_URL", env: env) ?? inferredCalDAVBaseURL(emailConfig)
            let carddavBase = optionalURL("\(prefix)CARDDAV_BASE_URL", env: env) ?? inferredCardDAVBaseURL(emailConfig)
            let webdavBase = optionalURL("\(prefix)WEBDAV_BASE_URL", env: env) ?? inferredWebDAVBaseURL(emailConfig)
            let defaultCalendars = (optional("\(prefix)CALDAV_CALENDAR_URLS", env: env) ?? "")
                .split(separator: ",")
                .compactMap { URL(string: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .ifEmpty(defaultCalendarURLs(emailConfig))
            return Account(
                accountID: emailConfig.accountID,
                email: emailConfig.fromAddress,
                username: emailConfig.imapUsername,
                password: emailConfig.imapPassword,
                caldavBaseURL: caldavBase,
                carddavBaseURL: carddavBase,
                webdavBaseURL: webdavBase,
                defaultCalendarURLs: defaultCalendars
            )
        }
    }

    private static func resolveAccounts(accountID: String?) -> [Account] {
        let accounts = loadAccounts()
        guard let accountID, !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return accounts.filter { $0.caldavBaseURL != nil || $0.carddavBaseURL != nil || $0.webdavBaseURL != nil || !$0.defaultCalendarURLs.isEmpty }
        }
        let normalized = JeffEmailClient.Config.normalizeAccountID(accountID)
        return accounts.filter { $0.accountID == normalized || $0.email.caseInsensitiveCompare(accountID) == .orderedSame }
    }

    private static func calendarCollections(account: Account) async throws -> [CalendarCollection] {
        if !account.defaultCalendarURLs.isEmpty {
            return account.defaultCalendarURLs.map { CalendarCollection(accountID: account.accountID, name: $0.lastPathComponent.ifEmpty($0.absoluteString), url: $0) }
        }
        guard let base = account.caldavBaseURL else {
            throw DAVError.unsupportedCapability(account.accountID, "caldav")
        }
        let home = try await discoverHomeSet(account: account, baseURL: base, property: "calendar-home-set")
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop><D:displayname/><D:resourcetype/><C:supported-calendar-component-set/></D:prop>
        </D:propfind>
        """
        let response = try await request(account: account, url: home, method: "PROPFIND", depth: "1", contentType: "application/xml; charset=utf-8", body: body)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return splitResponses(response.body).compactMap { block in
            guard block.range(of: #"<[^>]*:?calendar[\s/>]"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = extractFirst("href", from: block),
                  let url = resolveURL(href, relativeTo: home)
            else { return nil }
            let name = xmlText("displayname", in: block) ?? url.lastPathComponent.ifEmpty(url.absoluteString)
            return CalendarCollection(accountID: account.accountID, name: name, url: url)
        }
    }

    private static func queryEvents(account: Account, collection: CalendarCollection, start: Date, end: Date) async throws -> [CalendarEvent] {
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop><D:getetag/><C:calendar-data/></D:prop>
          <C:filter>
            <C:comp-filter name="VCALENDAR">
              <C:comp-filter name="VEVENT">
                <C:time-range start="\(calDAVDate(start))" end="\(calDAVDate(end))"/>
              </C:comp-filter>
            </C:comp-filter>
          </C:filter>
        </C:calendar-query>
        """
        let response = try await request(account: account, url: collection.url, method: "REPORT", depth: "1", contentType: "application/xml; charset=utf-8", body: body)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return splitResponses(response.body).flatMap { block -> [CalendarEvent] in
            guard let calendarData = xmlText("calendar-data", in: block) else { return [] }
            let eventURL = resolveURL(extractFirst("href", from: block) ?? "", relativeTo: collection.url)?.absoluteString
            return parseICSEvents(calendarData).map { parsed in
                CalendarEvent(
                    accountID: account.accountID,
                    calendarName: collection.name,
                    eventURL: eventURL,
                    uid: parsed["UID"],
                    summary: parsed["SUMMARY"],
                    start: parsed["DTSTART"],
                    end: parsed["DTEND"],
                    location: parsed["LOCATION"],
                    description: parsed["DESCRIPTION"]
                )
            }
        }
    }

    private static func busyIntervals(
        accounts: [Account],
        calendarURL: String?,
        start: Date,
        end: Date,
        timezone: TimeZone
    ) async -> (intervals: [BusyInterval], errors: [ToolErrorResult]) {
        await withTaskGroup(of: ([BusyInterval], [ToolErrorResult]).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let collections: [CalendarCollection]
                        if let calendarURL, let url = URL(string: calendarURL) {
                            collections = [CalendarCollection(accountID: account.accountID, name: calendarURL, url: url)]
                        } else {
                            collections = try await calendarCollections(account: account)
                        }

                        var intervals: [BusyInterval] = []
                        var errors: [ToolErrorResult] = []
                        for collection in collections.prefix(8) {
                            do {
                                let events = try await queryEvents(account: account, collection: collection, start: start, end: end)
                                intervals.append(contentsOf: events.compactMap { event in
                                    guard let eventStart = event.start.flatMap({ parseICSDateValue($0, timezone: timezone) }) else {
                                        return nil
                                    }
                                    let eventEnd = event.end.flatMap { parseICSDateValue($0, timezone: timezone) }
                                        ?? Calendar.current.date(byAdding: .hour, value: 1, to: eventStart)
                                        ?? eventStart
                                    guard eventEnd > start, eventStart < end else {
                                        return nil
                                    }
                                    return BusyInterval(
                                        start: max(eventStart, start),
                                        end: min(eventEnd, end),
                                        summary: event.summary,
                                        accountID: event.accountID,
                                        calendarName: event.calendarName
                                    )
                                })
                            } catch {
                                errors.append(ToolErrorResult(target: collection.url.absoluteString, error: String(describing: error)))
                            }
                        }
                        return (intervals, errors)
                    } catch {
                        return ([], [ToolErrorResult(target: account.accountID, error: String(describing: error))])
                    }
                }
            }

            var intervals: [BusyInterval] = []
            var errors: [ToolErrorResult] = []
            for await result in group {
                intervals.append(contentsOf: result.0)
                errors.append(contentsOf: result.1)
            }
            return (intervals, errors)
        }
    }

    private static func freeTimeSlots(
        windowStart: Date,
        windowEnd: Date,
        busyIntervals: [BusyInterval],
        durationMinutes: Int,
        timezone: TimeZone,
        dayStartHour: Int,
        dayEndHour: Int,
        limit: Int
    ) -> [FreeTimeSlot] {
        guard dayStartHour < dayEndHour else {
            return []
        }
        let minimumDuration = TimeInterval(durationMinutes * 60)
        let calendar = Calendar(identifier: .gregorian).withTimeZone(timezone)
        let mergedBusy = mergeBusyIntervals(busyIntervals)
        var slots: [FreeTimeSlot] = []
        var day = calendar.startOfDay(for: windowStart)
        let lastDay = calendar.startOfDay(for: windowEnd)

        while day <= lastDay, slots.count < limit {
            guard let dayWindowStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: day),
                  let dayWindowEnd = calendar.date(bySettingHour: dayEndHour == 24 ? 23 : dayEndHour, minute: dayEndHour == 24 ? 59 : 0, second: dayEndHour == 24 ? 59 : 0, of: day) else {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? windowEnd
                continue
            }
            var cursor = max(dayWindowStart, windowStart)
            let clippedDayEnd = min(dayWindowEnd, windowEnd)
            for busy in mergedBusy where busy.end > cursor && busy.start < clippedDayEnd {
                let freeEnd = min(busy.start, clippedDayEnd)
                if freeEnd.timeIntervalSince(cursor) >= minimumDuration {
                    slots.append(FreeTimeSlot(start: cursor, end: freeEnd, timezoneIdentifier: timezone.identifier))
                    if slots.count >= limit {
                        return slots
                    }
                }
                cursor = max(cursor, busy.end)
                if cursor >= clippedDayEnd {
                    break
                }
            }
            if clippedDayEnd.timeIntervalSince(cursor) >= minimumDuration, slots.count < limit {
                slots.append(FreeTimeSlot(start: cursor, end: clippedDayEnd, timezoneIdentifier: timezone.identifier))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? windowEnd
        }
        return slots
    }

    private static func mergeBusyIntervals(_ intervals: [BusyInterval]) -> [BusyInterval] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [BusyInterval] = []
        for interval in sorted {
            guard var last = merged.popLast() else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                last.end = max(last.end, interval.end)
                merged.append(last)
            } else {
                merged.append(last)
                merged.append(interval)
            }
        }
        return merged
    }

    private static func discoverAddressbooks(account: Account) async throws -> [URL] {
        guard let base = account.carddavBaseURL else {
            throw DAVError.unsupportedCapability(account.accountID, "carddav")
        }
        let home = try await discoverHomeSet(account: account, baseURL: base, property: "addressbook-home-set")
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
          <D:prop><D:displayname/><D:resourcetype/></D:prop>
        </D:propfind>
        """
        let response = try await request(account: account, url: home, method: "PROPFIND", depth: "1", contentType: "application/xml; charset=utf-8", body: body)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return splitResponses(response.body).compactMap { block in
            guard block.range(of: #"<[^>]*:?addressbook[\s/>]"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = extractFirst("href", from: block)
            else { return nil }
            return resolveURL(href, relativeTo: home)
        }
    }

    private static func queryContacts(account: Account, addressbook: URL, query: String, limit: Int) async throws -> [Contact] {
        let queryFilter: String
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            queryFilter = ""
        } else {
            let escaped = xmlEscape(trimmedQuery)
            queryFilter = """
              <C:filter test="anyof">
                <C:prop-filter name="FN"><C:text-match collation="i;unicode-casemap">\(escaped)</C:text-match></C:prop-filter>
                <C:prop-filter name="EMAIL"><C:text-match collation="i;unicode-casemap">\(escaped)</C:text-match></C:prop-filter>
                <C:prop-filter name="TEL"><C:text-match collation="i;unicode-casemap">\(escaped)</C:text-match></C:prop-filter>
                <C:prop-filter name="ORG"><C:text-match collation="i;unicode-casemap">\(escaped)</C:text-match></C:prop-filter>
              </C:filter>
            """
        }
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
          <D:prop><D:getetag/><C:address-data/></D:prop>
        \(queryFilter)
        </C:addressbook-query>
        """
        let response = try await request(account: account, url: addressbook, method: "REPORT", depth: "1", contentType: "application/xml; charset=utf-8", body: body)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw DAVError.httpStatus(response.statusCode, response.bodyPreview)
        }
        return splitResponses(response.body).prefix(limit).compactMap { block in
            guard let card = xmlText("address-data", in: block) else { return nil }
            let parsed = parseVCard(card)
            return Contact(
                accountID: account.accountID,
                sourceURL: resolveURL(extractFirst("href", from: block) ?? "", relativeTo: addressbook)?.absoluteString,
                fullName: parsed.single["FN"] ?? parsed.single["N"],
                emails: parsed.multi["EMAIL"] ?? [],
                phones: parsed.multi["TEL"] ?? [],
                organization: parsed.single["ORG"],
                title: parsed.single["TITLE"]
            )
        }
    }

    private static func discoverHomeSet(account: Account, baseURL: URL, property: String) async throws -> URL {
        let wellKnownPath = property == "addressbook-home-set" ? ".well-known/carddav" : ".well-known/caldav"
        let candidates = [appendPath(wellKnownPath, to: baseURL), baseURL]
        let principalBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CR="urn:ietf:params:xml:ns:carddav">
          <D:prop><D:current-user-principal/><C:calendar-home-set/><CR:addressbook-home-set/></D:prop>
        </D:propfind>
        """
        var lastError: Error?
        for candidate in candidates {
            do {
                let root = try await request(account: account, url: candidate, method: "PROPFIND", depth: "0", contentType: "application/xml; charset=utf-8", body: principalBody)
                guard root.statusCode == 207 || root.statusCode == 200 else {
                    throw DAVError.httpStatus(root.statusCode, root.bodyPreview)
                }
                if let direct = homeSetURL(named: property, xml: root.body, relativeTo: root.finalURL) {
                    return direct
                }
                if property == "calendar-home-set",
                   root.body.range(of: "calendar-query", options: .caseInsensitive) != nil {
                    return root.finalURL
                }
                if property == "addressbook-home-set",
                   root.body.range(of: "addressbook-query", options: .caseInsensitive) != nil {
                    return root.finalURL
                }
                if let principalHref = nestedHref(named: "current-user-principal", xml: root.body),
                   let principalURL = resolveURL(principalHref, relativeTo: root.finalURL) {
                    let principal = try await request(account: account, url: principalURL, method: "PROPFIND", depth: "0", contentType: "application/xml; charset=utf-8", body: principalBody)
                    guard principal.statusCode == 207 || principal.statusCode == 200 else {
                        throw DAVError.httpStatus(principal.statusCode, principal.bodyPreview)
                    }
                    if let discovered = homeSetURL(named: property, xml: principal.body, relativeTo: principal.finalURL) {
                        return discovered
                    }
                    if property == "calendar-home-set",
                       principal.body.range(of: "calendar-query", options: .caseInsensitive) != nil {
                        return principal.finalURL
                    }
                    if property == "addressbook-home-set",
                       principal.body.range(of: "addressbook-query", options: .caseInsensitive) != nil {
                        return principal.finalURL
                    }
                }
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        throw DAVError.discoveryFailed(account.accountID, property)
    }

    private static func request(
        account: Account,
        url: URL,
        method: String,
        depth: String? = nil,
        contentType: String? = nil,
        body: String?
    ) async throws -> DAVResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Basic \(basicAuth(username: account.username, password: account.password))", forHTTPHeaderField: "Authorization")
        request.setValue("OmniKit-Jeff/1.0", forHTTPHeaderField: "User-Agent")
        if let depth {
            request.setValue(depth, forHTTPHeaderField: "Depth")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body {
            request.httpBody = body.data(using: .utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        return DAVResponse(statusCode: statusCode, body: text, finalURL: response.url ?? url)
    }

    private static func inferredCalDAVBaseURL(_ config: JeffEmailClient.Config) -> URL? {
        switch config.imapHost.lowercased() {
        case "imap.purelymail.com":
            return URL(string: "https://purelymail.com/")
        case "imap.migadu.com":
            return URL(string: "https://cdav.migadu.com/")
        case "imap.mail.me.com":
            return URL(string: "https://caldav.icloud.com/")
        default:
            return nil
        }
    }

    private static func inferredCardDAVBaseURL(_ config: JeffEmailClient.Config) -> URL? {
        switch config.imapHost.lowercased() {
        case "imap.purelymail.com":
            return URL(string: "https://purelymail.com/")
        case "imap.mail.me.com":
            return URL(string: "https://contacts.icloud.com/")
        default:
            return nil
        }
    }

    private static func inferredWebDAVBaseURL(_ config: JeffEmailClient.Config) -> URL? {
        switch config.imapHost.lowercased() {
        case "imap.purelymail.com":
            return URL(string: "https://purelymail.com/webdav/")
        default:
            return nil
        }
    }

    private static func defaultCalendarURLs(_ config: JeffEmailClient.Config) -> [URL] {
        guard config.imapHost.lowercased() == "imap.migadu.com" else {
            return []
        }
        let escapedAddress = config.imapUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.imapUsername
        return [
            URL(string: "https://cdav.migadu.com/calendars/\(escapedAddress)/home"),
            URL(string: "https://cdav.migadu.com/calendars/\(escapedAddress)/work"),
        ].compactMap { $0 }
    }

    private static func loadDotEnv() -> [String: String] {
        guard let data = try? String(contentsOfFile: ".env", encoding: .utf8) else {
            return [:]
        }
        var values: [String: String] = [:]
        for rawLine in data.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
                if first == "\"" {
                    value = decodeEscapes(value)
                }
            }
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func optional(_ key: String, env: [String: String]) -> String? {
        let value = env[key].map(decodeEscapes)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func optionalURL(_ key: String, env: [String: String]) -> URL? {
        optional(key, env: env).flatMap(URL.init(string:))
    }

    private static func decodeEscapes(_ rawValue: String) -> String {
        var decoded = ""
        var iterator = rawValue.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                decoded.append(character)
                continue
            }
            guard let escaped = iterator.next() else {
                decoded.append(character)
                break
            }
            switch escaped {
            case "n": decoded.append("\n")
            case "r": decoded.append("\r")
            case "t": decoded.append("\t")
            case "\\": decoded.append("\\")
            case "\"": decoded.append("\"")
            default:
                decoded.append("\\")
                decoded.append(escaped)
            }
        }
        return decoded
    }
}

private struct DAVResponse: Sendable {
    var statusCode: Int
    var body: String
    var finalURL: URL
    var bodyPreview: String {
        String(body.prefix(500))
    }
}

enum DAVError: Error, CustomStringConvertible {
    case noDAVAccount(String)
    case unsupportedCapability(String, String)
    case noCalendarCollection(String)
    case invalidURL(String)
    case invalidDate(String)
    case httpStatus(Int, String)
    case discoveryFailed(String, String)

    var description: String {
        switch self {
        case .noDAVAccount(let accountID):
            return "No DAV-capable account found for '\(accountID)'."
        case .unsupportedCapability(let accountID, let capability):
            return "Account '\(accountID)' is not configured for \(capability)."
        case .noCalendarCollection(let accountID):
            return "No calendar collection found for account '\(accountID)'."
        case .invalidURL(let rawURL):
            return "Invalid URL '\(rawURL)'."
        case .invalidDate(let value):
            return "Invalid date '\(value)'. Use ISO-8601."
        case .httpStatus(let status, let body):
            return "DAV request failed with HTTP \(status): \(body)"
        case .discoveryFailed(let accountID, let property):
            return "DAV discovery failed for account '\(accountID)' while resolving \(property)."
        }
    }
}

private func basicAuth(username: String, password: String) -> String {
    Data("\(username):\(password)".utf8).base64EncodedString()
}

private func splitResponses(_ xml: String) -> [String] {
    allMatches(#"(?is)<[^>]*:?response\b[^>]*>.*?</[^>]*:?response>"#, in: xml)
}

private func extractFirst(_ tag: String, from xml: String) -> String? {
    xmlText(tag, in: xml)
}

private func xmlText(_ tag: String, in xml: String) -> String? {
    guard let raw = firstMatch(#"(?is)<[^>]*:?\#(tag)\b[^>]*>(.*?)</[^>]*:?\#(tag)>"#, in: xml) else {
        return nil
    }
    return xmlUnescape(raw).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func nestedHref(named tag: String, xml: String) -> String? {
    guard let block = firstMatch(#"(?is)<[^>]*:?\#(tag)\b[^>]*>(.*?)</[^>]*:?\#(tag)>"#, in: xml) else {
        return nil
    }
    return xmlText("href", in: block)
}

private func homeSetURL(named tag: String, xml: String, relativeTo baseURL: URL) -> URL? {
    nestedHref(named: tag, xml: xml).flatMap { resolveURL($0, relativeTo: baseURL) }
}

private func allMatches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        guard let range = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

private func firstMatch(_ pattern: String, in text: String) -> String? {
    allMatches(pattern, in: text).first
}

private func xmlUnescape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private func resolveURL(_ href: String, relativeTo baseURL: URL) -> URL? {
    let unescaped = xmlUnescape(href).trimmingCharacters(in: .whitespacesAndNewlines)
    if let absolute = URL(string: unescaped), absolute.scheme != nil {
        return absolute
    }
    return URL(string: unescaped, relativeTo: baseURL)?.absoluteURL
}

private func appendPath(_ path: String?, to base: URL) -> URL {
    let cleanPath = (path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !cleanPath.isEmpty else { return base }
    return cleanPath.split(separator: "/").reduce(base) { url, component in
        url.appendingPathComponent(String(component))
    }
}

private func calDAVDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: date)
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func localDisplayString(_ date: Date, timezone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timezone
    formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
    return formatter.string(from: date)
}

private func parseDate(_ value: String) throws -> Date {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: trimmed) {
        return date
    }
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: trimmed) {
        return date
    }
    throw DAVError.invalidDate(value)
}

private func parseICSDateValue(_ value: String, timezone: TimeZone) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formats: [(String, TimeZone)] = [
        ("yyyyMMdd'T'HHmmss'Z'", TimeZone(secondsFromGMT: 0) ?? timezone),
        ("yyyyMMdd'T'HHmmss", timezone),
        ("yyyyMMdd", timezone),
    ]
    for (format, formatterTimezone) in formats {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = formatterTimezone
        formatter.dateFormat = format
        if let date = formatter.date(from: trimmed) {
            return date
        }
    }
    return try? parseDate(trimmed)
}

private func buildICS(uid: String, title: String, start: Date, end: Date, location: String?, notes: String?) -> String {
    let stamp = calDAVDate(Date())
    let locationLine = line("LOCATION", location)
    let descriptionLine = line("DESCRIPTION", notes)
    return """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//OmniKit Jeff//EA Calendar//EN
    BEGIN:VEVENT
    UID:\(escapeICSText(uid))
    DTSTAMP:\(stamp)
    DTSTART:\(calDAVDate(start))
    DTEND:\(calDAVDate(end))
    SUMMARY:\(escapeICSText(title))
    \(locationLine)\(descriptionLine)END:VEVENT
    END:VCALENDAR
    """
}

private func line(_ key: String, _ value: String?) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return ""
    }
    return "\(key):\(escapeICSText(value))\n"
}

private func escapeICSText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: ",", with: "\\,")
        .replacingOccurrences(of: ";", with: "\\;")
}

private func parseICSEvents(_ ics: String) -> [[String: String]] {
    let unfolded = unfoldICS(ics)
    var events: [[String: String]] = []
    var current: [String: String]?
    for line in unfolded {
        if line == "BEGIN:VEVENT" {
            current = [:]
            continue
        }
        if line == "END:VEVENT" {
            if let current {
                events.append(current)
            }
            current = nil
            continue
        }
        guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
        let rawKey = String(line[..<colon])
        let key = rawKey.split(separator: ";").first.map(String.init) ?? rawKey
        let value = String(line[line.index(after: colon)...])
        if ["UID", "SUMMARY", "DTSTART", "DTEND", "LOCATION", "DESCRIPTION"].contains(key) {
            current?[key] = unescapeICSText(value)
        }
    }
    return events
}

private func parseVCard(_ vcard: String) -> (single: [String: String], multi: [String: [String]]) {
    let unfolded = unfoldICS(vcard)
    var single: [String: String] = [:]
    var multi: [String: [String]] = [:]
    for line in unfolded {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let rawKey = String(line[..<colon])
        let key = rawKey.split(separator: ";").first.map(String.init) ?? rawKey
        let value = unescapeICSText(String(line[line.index(after: colon)...]))
        switch key {
        case "FN", "N", "ORG", "TITLE":
            single[key] = value
        case "EMAIL", "TEL":
            multi[key, default: []].append(value)
        default:
            continue
        }
    }
    return (single, multi)
}

private func unfoldICS(_ text: String) -> [String] {
    var lines: [String] = []
    for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
            lines[lines.count - 1] += String(line.dropFirst())
        } else {
            lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    return lines
}

private func unescapeICSText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\N", with: "\n")
        .replacingOccurrences(of: "\\,", with: ",")
        .replacingOccurrences(of: "\\;", with: ";")
        .replacingOccurrences(of: "\\\\", with: "\\")
}

private extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}

private extension Calendar {
    func withTimeZone(_ timezone: TimeZone) -> Calendar {
        var copy = self
        copy.timeZone = timezone
        return copy
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
