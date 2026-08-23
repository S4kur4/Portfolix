import Foundation

public enum AutomaticPriceUpdateSchedule {
    public static let enabledSettingKey = "automatic_price_updates_enabled"
    public static let frequencySettingKey = "automatic_price_update_frequency"
    public static let dailyTimeSettingKey = "automatic_price_update_daily_time_minutes"
    public static let scheduleAnchorSettingKey = "automatic_price_update_schedule_anchor_at"
    public static let lastRunSettingKey = "automatic_price_update_last_run_at"

    public static func nextDelaySeconds(
        frequency: String,
        dailyTimeMinutes: Int = 9 * 60,
        scheduleAnchor: Date?,
        lastRun: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        if let interval = intervalSeconds(for: frequency) {
            let reference = [scheduleAnchor, lastRun]
                .compactMap { $0 }
                .max() ?? now
            let dueDate = reference.addingTimeInterval(TimeInterval(interval))
            return max(0, Int(ceil(dueDate.timeIntervalSince(now))))
        }

        let minutes = min(max(dailyTimeMinutes, 0), 23 * 60 + 59)
        let reference = [scheduleAnchor, lastRun]
            .compactMap { $0 }
            .max() ?? now
        let startOfToday = calendar.startOfDay(for: now)
        let todayRun = calendar.date(byAdding: .minute, value: minutes, to: startOfToday) ?? now

        if now < todayRun {
            return max(0, Int(ceil(todayRun.timeIntervalSince(now))))
        }
        if reference < todayRun {
            return 0
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(24 * 60 * 60)
        let nextRun = calendar.date(byAdding: .minute, value: minutes, to: tomorrow)
            ?? tomorrow
        return max(0, Int(ceil(nextRun.timeIntervalSince(now))))
    }

    private static func intervalSeconds(for frequency: String) -> Int? {
        switch frequency {
        case "5 分钟": 5 * 60
        case "15 分钟": 15 * 60
        case "30 分钟": 30 * 60
        case "1 小时": 60 * 60
        case "4 小时": 4 * 60 * 60
        case "8 小时": 8 * 60 * 60
        case "每日", "每日固定时间": nil
        default: 60 * 60
        }
    }
}
