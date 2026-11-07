import SwiftUI

/// One glass surface keeps calendar navigation and time menus aligned with form controls.
struct PortfolixDateTimePicker: View {
    let title: String
    @Binding var selection: Date
    let language: AppLanguage
    var includesTime = true
    @Binding var isPresented: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme

    private var localCalendar: Calendar {
        var result = calendar
        result.timeZone = timeZone
        return result
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: selection)
    }

    private func text(_ cn: String, _ en: String) -> String {
        localizedText(cn, en, language: language)
    }

    private func timeSelection(_ component: Calendar.Component) -> Binding<Int> {
        Binding(get: { localCalendar.component(component, from: selection) }, set: { value in
            let hour = component == .hour ? value : localCalendar.component(.hour, from: selection)
            let minute = component == .minute ? value : localCalendar.component(.minute, from: selection)
            if let date = localCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: selection) {
                selection = min(date, .now)
            }
        })
    }

    private var hours: [Int] {
        Array(0...(localCalendar.isDateInToday(selection) ? localCalendar.component(.hour, from: .now) : 23))
    }

    private var minutes: [Int] {
        let now = Date.now
        let isCurrentHour = localCalendar.isDate(selection, inSameDayAs: now)
            && localCalendar.component(.hour, from: selection) == localCalendar.component(.hour, from: now)
        return Array(0...(isCurrentHour ? localCalendar.component(.minute, from: now) : 59))
    }

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Button { isPresented.toggle() } label: {
                HStack(spacing: PortfolixSpacing.sm) {
                    Image(systemName: "calendar").foregroundStyle(PortfolixTheme.secondaryText)
                    Text(dateText).monospacedDigit()
                }
                .frame(height: PortfolixLayout.glassControlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("选择日期", "Choose Date"))
            .accessibilityValue(dateText)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PortfolixDateTimeEditor(selection: $selection, language: language) { isPresented = false }
                    .preferredColorScheme(colorScheme)
            }

            if includesTime {
                Rectangle().fill(PortfolixTheme.border)
                    .frame(width: 0.5, height: PortfolixSpacing.md)
                HStack(spacing: PortfolixSpacing.xs) {
                    timeMenu(.hour, title: text("小时（24 小时制）", "Hour (24-hour clock)"), options: hours)
                    Text(":").foregroundStyle(PortfolixTheme.secondaryText)
                    timeMenu(.minute, title: text("分钟", "Minute"), options: minutes)
                }
            }
        }
        .font(PortfolixTypography.captionEmphasis)
        .foregroundStyle(PortfolixTheme.glassControlText)
        .padding(.horizontal, PortfolixSpacing.sm)
        .portfolixGlassControl()
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func timeMenu(_ component: Calendar.Component, title: String, options: [Int]) -> some View {
        let binding = timeSelection(component)
        return Menu {
            ForEach(options, id: \.self) { value in
                Button(String(format: "%02d", value)) { binding.wrappedValue = value }
            }
        } label: {
            HStack(spacing: PortfolixSpacing.xs) {
                Text(String(format: "%02d", binding.wrappedValue)).monospacedDigit()
                if component == .minute {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.secondaryText)
                }
            }
            .frame(height: PortfolixLayout.glassControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%02d", binding.wrappedValue))
    }
}

struct PortfolixDateTimeEditor: View {
    @Binding var selection: Date
    let language: AppLanguage
    let onDone: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    private var dateSelection: Binding<Date> {
        Binding(get: { selection }, set: { date in
            var calendar = calendar
            calendar.timeZone = timeZone
            let components = calendar.dateComponents([.hour, .minute, .second], from: selection)
            let updated = calendar.date(bySettingHour: components.hour ?? 0,
                minute: components.minute ?? 0, second: components.second ?? 0, of: date) ?? date
            selection = min(updated, .now)
        })
    }

    var body: some View {
        VStack(spacing: PortfolixSpacing.md) {
            DatePicker(localizedText("日期", "Date", language: language), selection: dateSelection,
                in: Date(timeIntervalSince1970: 0)...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(PortfolixTheme.lilac)
                .environment(\.locale, Locale(identifier: language == .english ? "en_US" : "zh_CN"))
                .fixedSize()
            HStack(spacing: PortfolixSpacing.sm) {
                Button(localizedText("此刻", "Now", language: language)) { selection = .now }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button(localizedText("完成", "Done", language: language), action: onDone)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        // Let the calendar's intrinsic width define the button row as well.
        .fixedSize(horizontal: true, vertical: true)
        .padding(PortfolixSpacing.lg)
        .background(PortfolixTheme.panel)
        .onExitCommand(perform: onDone)
    }
}
