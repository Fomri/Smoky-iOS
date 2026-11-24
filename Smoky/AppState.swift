import Foundation
import Combine

// MARK: - Enums

public enum DayOfWeek: Int, Codable, CaseIterable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday
}

public enum LogEventType: String, Codable {
    case scheduled
    case skipped
    case sacrificed
}

public enum ExtraLogType: String, Codable {
    case swapped
    case unexpected
}

public enum AppTab: String, Codable {
    case today
    case schedule
    case stats
}

public enum ScheduleMode: String, Codable {
    case recurring
    case next
}

// MARK: - Models

public struct Slot: Codable, Equatable, Identifiable {
    public let id: String
    public let time: String // "HH:mm"
    public let label: String
    public var count: Int
    
    public init(id: String, time: String, label: String, count: Int = 0) {
        self.id = id
        self.time = time
        self.label = label
        self.count = count
    }
}

public struct LogEvent: Codable, Equatable {
    public let type: LogEventType
    public let timestamp: String
    public let ts: Int64?

    public init(type: LogEventType, timestamp: String, ts: Int64?) {
        self.type = type
        self.timestamp = timestamp
        self.ts = ts
    }
}

public struct DaySlotLog: Codable, Equatable, Identifiable {
    public let slotId: String
    public let time: String
    public let label: String
    
    public var allowance: Int
    public var smokedCount: Int
    public var sacrificedCount: Int
    public var skippedCount: Int
    
    public var events: [LogEvent]
    
    public var id: String { slotId }
    
    public init(
        slotId: String,
        time: String,
        label: String,
        allowance: Int = 0,
        smokedCount: Int = 0,
        sacrificedCount: Int = 0,
        skippedCount: Int = 0,
        events: [LogEvent] = []
    ) {
        self.slotId = slotId
        self.time = time
        self.label = label
        self.allowance = allowance
        self.smokedCount = smokedCount
        self.sacrificedCount = sacrificedCount
        self.skippedCount = skippedCount
        self.events = events
    }
}

public struct ExtraLog: Codable, Equatable, Identifiable {
    public let id: String
    public let type: ExtraLogType
    public let timestamp: String // ISO8601 string
    public let ts: Int64? // unix ms timestamp
    
    public let reason: String?
    
    public let sacrificedSlotId: String?
    public let sacrificedSlotLabel: String?
    
    public let fromSkipped: Bool?
    public let skippedAt: String?
    
    public init(
        id: String,
        type: ExtraLogType,
        timestamp: String,
        ts: Int64?,
        reason: String? = nil,
        sacrificedSlotId: String? = nil,
        sacrificedSlotLabel: String? = nil,
        fromSkipped: Bool? = nil,
        skippedAt: String? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.ts = ts
        self.reason = reason
        self.sacrificedSlotId = sacrificedSlotId
        self.sacrificedSlotLabel = sacrificedSlotLabel
        self.fromSkipped = fromSkipped
        self.skippedAt = skippedAt
    }
}

public struct AppLog: Codable, Equatable {
    public let date: String // "YYYY-MM-DD"
    public let dayOfWeek: Int // 0-6 Sunday=0
    public var slots: [DaySlotLog]
    public var extraLogs: [ExtraLog]
    
    public init(date: String, dayOfWeek: Int, slots: [DaySlotLog] = [], extraLogs: [ExtraLog] = []) {
        self.date = date
        self.dayOfWeek = dayOfWeek
        self.slots = slots
        self.extraLogs = extraLogs
    }
}

public struct AppData: Codable, Equatable {
    public var schedule: [Int: [Slot]] // dayOfWeek Int -> [Slot]
    public var scheduleOverrides: [String: [Slot]] // date string -> [Slot]
    public var logs: [String: AppLog] // date string -> AppLog
    public var startedAt: String // ISO8601

    public init(
        schedule: [Int: [Slot]] = [:],
        scheduleOverrides: [String: [Slot]] = [:],
        logs: [String: AppLog] = [:],
        startedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.schedule = schedule
        self.scheduleOverrides = scheduleOverrides
        self.logs = logs
        self.startedAt = startedAt
    }
}

// MARK: - AppState

@MainActor
public class AppState: ObservableObject {
    public enum ActionError: Error {
        case slotNotFound
        case slotNotLogged
        case noLogForToday
        case invalidReason
    }

    @Published public var activeTab: AppTab = .today
    @Published public var selectedScheduleDay: Int = DayOfWeek.monday.rawValue
    @Published public var scheduleMode: ScheduleMode = .recurring
    @Published public var data: AppData = AppData()
    
    private let userDefaultsKey = "Smoky_v1_data"
    
    public init() {
        load()
    }
    
    // MARK: - Persistence
    
    public func load() {
        if let stored = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.data = try decoder.decode(AppData.self, from: stored)
                return
            } catch {
                // fall through to sample schedule on decode failure
            }
        }
        self.data = createSampleSchedule()
        save()
    }
    
    public func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let encoded = try encoder.encode(data)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            // silently fail
        }
    }
    
    // MARK: - Sample Schedule
    
    public func createSampleSchedule() -> AppData {
        // weekday slots
        let weekdaySlots: [Slot] = [
            Slot(id: "s1", time: "07:00", label: "Wake Up"),
            Slot(id: "s2", time: "08:00", label: "Breakfast"),
            Slot(id: "s3", time: "12:00", label: "Lunch"),
            Slot(id: "s4", time: "17:00", label: "Dinner"),
            Slot(id: "s5", time: "21:00", label: "Before Sleep"),
        ].map {
            Slot(id: $0.id, time: $0.time, label: $0.label, count: 1)
        }
        // weekend slots (more relaxed, fewer)
        let weekendSlots: [Slot] = [
            Slot(id: "w1", time: "09:00", label: "Wake Up"),
            Slot(id: "w2", time: "13:00", label: "Lunch"),
            Slot(id: "w3", time: "20:00", label: "Evening"),
        ].map { Slot(id: $0.id, time: $0.time, label: $0.label, count: 2) }
        
        var scheduleDict: [Int: [Slot]] = [:]
        for day in 0...6 {
            if day == DayOfWeek.saturday.rawValue || day == DayOfWeek.sunday.rawValue {
                scheduleDict[day] = weekendSlots
            } else {
                scheduleDict[day] = weekdaySlots
            }
        }
        
        return AppData(schedule: scheduleDict, scheduleOverrides: [:], logs: [:], startedAt: ISO8601DateFormatter().string(from: Date()))
    }
    
    // MARK: - Helpers for Dates/Times
    
    public static func uid() -> String {
        UUID().uuidString
    }
    
    public static func getLogicalNow() -> Date {
        Date()
    }
    
    /// Returns date string "YYYY-MM-DD" for today plus offset in days.
    public static func getTodayKey(offset: Int = 0) -> String {
        let calendar = Calendar.current
        let base = Date()
        guard let targetDate = calendar.date(byAdding: .day, value: offset, to: base) else {
            return formatDate(base)
        }
        return formatDate(targetDate)
    }
    
    /// Format Date to "YYYY-MM-DD"
    public static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
    
    /// Format display date like "Tue, Mar 9"
    public static func formatDisplayDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date)
    }
    
    /// Format display date from "YYYY-MM-DD"
    public static func formatDisplayDate(dateKey: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateKey) else { return dateKey }
        return formatDisplayDate(date)
    }
    
    
    /// Return Date for a given weekday (0=Sunday) on or after the reference date.
    public static func getNextDateForWeekday(_ weekday: Int, from referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        let weekdayIndex = (weekday % 7) + 1 // Sunday=1 .. Saturday=7
        var components = calendar.dateComponents([.year, .month, .day, .weekday], from: referenceDate)
        let currentWeekday = components.weekday ?? 1
        
        var offsetDays = weekdayIndex - currentWeekday
        if offsetDays < 0 { offsetDays += 7 }
        
        if offsetDays == 0 {
            // Today is the day
            return calendar.startOfDay(for: referenceDate)
        }
        guard let nextDate = calendar.date(byAdding: .day, value: offsetDays, to: calendar.startOfDay(for: referenceDate)) else {
            return referenceDate
        }
        return nextDate
    }
    
    /// Convert "HH:mm" string to total minutes after midnight
    public static func timeToMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0..<24).contains(h),
              (0..<60).contains(m) else {
            return nil
        }
        return h * 60 + m
    }
    
    /// Returns current time string "HH:mm"
    public static func getCurrentTimeStr() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }
    
    // MARK: - Schedule
    
    /// Returns date key for schedule target based on mode and selected day
    public func getScheduleTargetDate() -> String {
        switch scheduleMode {
        case .recurring:
            // return key for the selected weekday for this week (or next)
            let day = selectedScheduleDay
            let date = Self.getNextDateForWeekday(day)
            return Self.formatDate(date)
        case .next:
            // next day after today
            return Self.getTodayKey(offset: 1)
        }
    }
    
    /// Returns slots for a given dayOfWeek or schedule override dateKey if exists
    public func getScheduleSlotsForDay(dayOfWeek: Int? = nil, dateKey: String? = nil) -> [Slot] {
        if let dateKey = dateKey, let overrideSlots = self.data.scheduleOverrides[dateKey] {
            return overrideSlots
        }
        let d = dayOfWeek ?? selectedScheduleDay
        return self.data.schedule[d] ?? []
    }
    
    /// Set slots for the currently selected schedule day or dateKey override
    public func setScheduleSlotsForSelectedDay(slots: [Slot]) {
        switch scheduleMode {
        case .recurring:
            self.data.schedule[selectedScheduleDay] = slots
        case .next:
            let dateKey = getScheduleTargetDate()
            self.data.scheduleOverrides[dateKey] = slots
        }
        save()
    }
    
    // MARK: - Logs & Metrics
    
    /// Ensure AppLog exists for today, creating from schedule if needed
    public func ensureTodayLog() -> AppLog {
        let todayKey = Self.getTodayKey()
        if let existing = self.data.logs[todayKey] { return existing }

        // create new log for today
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: Date())
        let dayOfWeek = calendar.component(.weekday, from: date) - 1 // Sunday=0
        let slotsForToday = getScheduleSlotsForDay(dayOfWeek: dayOfWeek)

        let logSlots = slotsForToday.map {
            DaySlotLog(
                slotId: $0.id,
                time: $0.time,
                label: $0.label,
                allowance: $0.count,
                smokedCount: 0,
                sacrificedCount: 0,
                skippedCount: 0,
                events: []
            )
        }
        let newLog = AppLog(date: todayKey, dayOfWeek: dayOfWeek, slots: logSlots, extraLogs: [])
        self.data.logs[todayKey] = newLog
        save()
        return newLog
    }
    
    /// Returns summary metrics for a given day's log
    public func getDayMetrics(log: AppLog) -> (totalAllowance: Int, smoked: Int, sacrificed: Int, skipped: Int) {
        let totalAllowance = log.slots.reduce(0) { $0 + $1.allowance }
        let smoked = log.slots.reduce(0) { $0 + $1.smokedCount }
        let sacrificed = log.slots.reduce(0) { $0 + $1.sacrificedCount }
        let skipped = log.slots.reduce(0) { $0 + $1.skippedCount }
        return (totalAllowance, smoked, sacrificed, skipped)
    }
    
    /// Create event timestamp string and ts for now or from dateKey and time
    public static func eventTs(dateKey: String, ev: LogEventType) -> (timestamp: String, ts: Int64) {
        // timestamp as ISO8601 string with time of now
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
        let ts = Int64(now.timeIntervalSince1970 * 1000)
        return (timestamp, ts)
    }
    
    /// Get all smoked times (Date) for a given log
    public func getSmokeTimes(log: AppLog) -> [Date] {
        var results: [Date] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for slot in log.slots {
            for event in slot.events where event.type == .scheduled {
                if let ts = event.ts {
                    results.append(Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
                } else if let date = isoFormatter.date(from: event.timestamp) {
                    results.append(date)
                }
            }
        }
        for extra in log.extraLogs {
            if extra.type == .unexpected {
                if let ts = extra.ts {
                    results.append(Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
                } else if let date = isoFormatter.date(from: extra.timestamp) {
                    results.append(date)
                }
            }
        }
        return results.sorted(by: { $0 < $1 })
    }
    
    /// Returns timestamp (ms) of last smoked event or nil
    public func getLastSmokeTs(log: AppLog) -> Int64? {
        let allTs: [Int64] = log.slots.flatMap { slot in
            slot.events.compactMap { $0.type == .scheduled ? $0.ts : nil }
        } + log.extraLogs.filter { $0.type == .unexpected }.compactMap { $0.ts }
        
        return allTs.max()
    }
    
    /// Average gap in milliseconds between smoked events in the log
    public func getAvgGapMs(log: AppLog) -> Double? {
        let times = getSmokeTimes(log: log)
        guard times.count > 1 else { return nil }
        var gapsInSeconds: [Double] = []
        for idx in 1..<times.count {
            let gap = times[idx].timeIntervalSince(times[idx-1])
            gapsInSeconds.append(gap)
        }
        return gapsInSeconds.reduce(0, +) / Double(gapsInSeconds.count)
    }
    
    /// Format gap in seconds to human-readable string
    public static func formatGap(seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0f secs", seconds)
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            return "\(mins) min" + (mins > 1 ? "s" : "")
        } else {
            let hours = seconds / 3600
            return String(format: "%.1f hours", hours)
        }
    }
    
    /// Format stopwatch ms duration to "HH:mm:ss"
    public static func formatStopwatch(milliseconds: Int64) -> String {
        let totalSeconds = milliseconds / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
    // MARK: - Action Functions
    
    /// Mark a slot smoked now for today
    @discardableResult
    public func markSlotSmoked(slotId: String) throws {
        let todayKey = Self.getTodayKey()
        guard var log = self.data.logs[todayKey] else {
            throw ActionError.noLogForToday
        }
        guard let idx = log.slots.firstIndex(where: { $0.slotId == slotId }) else {
            throw ActionError.slotNotFound
        }
        var slotLog = log.slots[idx]
        // increment smoked count
        slotLog.smokedCount += 1
        
        // add event
        let (timestamp, ts) = Self.eventTs(dateKey: todayKey, ev: .scheduled)
        let event = LogEvent(type: .scheduled, timestamp: timestamp, ts: ts)
        slotLog.events.append(event)
        
        // update slot log and main log
        log.slots[idx] = slotLog
        self.data.logs[todayKey] = log
        save()
    }
    
    /// Mark a slot as skipped for today
    @discardableResult
    public func markSlotSkipped(slotId: String) throws {
        let todayKey = Self.getTodayKey()
        guard var log = self.data.logs[todayKey] else {
            throw ActionError.noLogForToday
        }
        guard let idx = log.slots.firstIndex(where: { $0.slotId == slotId }) else {
            throw ActionError.slotNotFound
        }
        var slotLog = log.slots[idx]
        // increment skipped count
        slotLog.skippedCount += 1
        
        // add skipped event
        let (timestamp, ts) = Self.eventTs(dateKey: todayKey, ev: .skipped)
        let event = LogEvent(type: .skipped, timestamp: timestamp, ts: ts)
        slotLog.events.append(event)
        
        // update and save
        log.slots[idx] = slotLog
        self.data.logs[todayKey] = log
        save()
    }
    
    /// Undo last action on slot for today for smoked/skipped/sacrificed event
    @discardableResult
    public func undoSlotAction(slotId: String) throws {
        let todayKey = Self.getTodayKey()
        guard var log = self.data.logs[todayKey] else {
            throw ActionError.noLogForToday
        }
        guard let idx = log.slots.firstIndex(where: { $0.slotId == slotId }) else {
            throw ActionError.slotNotFound
        }
        var slotLog = log.slots[idx]
        // remove last event if any
        guard let lastEvent = slotLog.events.last else {
            throw ActionError.slotNotLogged
        }
        switch lastEvent.type {
        case .scheduled:
            if slotLog.smokedCount > 0 {
                slotLog.smokedCount -= 1
            }
        case .skipped:
            if slotLog.skippedCount > 0 {
                slotLog.skippedCount -= 1
            }
        case .sacrificed:
            if slotLog.sacrificedCount > 0 {
                slotLog.sacrificedCount -= 1
            }
        }
        slotLog.events.removeLast()
        
        // update and save
        log.slots[idx] = slotLog
        self.data.logs[todayKey] = log
        save()
    }
    
    /// Confirm swapped slot action
    public func confirmSwapSlot(slotId: String, fromSkipped: Bool) throws {
        let todayKey = Self.getTodayKey()
        guard var log = self.data.logs[todayKey] else {
            throw ActionError.noLogForToday
        }
        // find slot log
        guard let idx = log.slots.firstIndex(where: { $0.slotId == slotId }) else {
            throw ActionError.slotNotFound
        }
        var slotLog = log.slots[idx]
        
        // Add sacrificed count and event
        slotLog.sacrificedCount += 1
        let (timestamp, ts) = Self.eventTs(dateKey: todayKey, ev: .sacrificed)
        let sacrificeEvent = LogEvent(type: .sacrificed, timestamp: timestamp, ts: ts)
        slotLog.events.append(sacrificeEvent)
        
        // Add extra log record for swapped
        let extraLog = ExtraLog(
            id: Self.uid(),
            type: .swapped,
            timestamp: timestamp,
            ts: ts,
            reason: nil,
            sacrificedSlotId: slotId,
            sacrificedSlotLabel: slotLog.label,
            fromSkipped: fromSkipped,
            skippedAt: fromSkipped ? timestamp : nil
        )
        log.extraLogs.append(extraLog)
        
        // update slot log and main log
        log.slots[idx] = slotLog
        self.data.logs[todayKey] = log
        save()
    }
    
    /// Confirm unexpected smoke event with optional reason
    public func confirmUnexpectedSmoke(reason: String?) throws {
        let todayKey = Self.getTodayKey()
        guard !todayKey.isEmpty else {
            throw ActionError.noLogForToday
        }
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
        let ts = Int64(now.timeIntervalSince1970 * 1000)
        if let reason = reason, reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ActionError.invalidReason
        }
        let extraLog = ExtraLog(
            id: Self.uid(),
            type: .unexpected,
            timestamp: timestamp,
            ts: ts,
            reason: reason,
            sacrificedSlotId: nil,
            sacrificedSlotLabel: nil,
            fromSkipped: nil,
            skippedAt: nil
        )
        if self.data.logs[todayKey] == nil {
            // create empty log with slots from schedule
            _ = ensureTodayLog()
        }
        self.data.logs[todayKey]?.extraLogs.append(extraLog)
        save()
    }
}
