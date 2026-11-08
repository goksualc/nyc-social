import SwiftUI

// MARK: - Glass surfaces

extension View {
    /// Translucent dark surface used by the floating controls over the map.
    func alongGlass(in shape: some Shape = Capsule(), tint: Double = 0.55) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background(AlongColor.navy.opacity(tint), in: shape)
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }
}

/// A round floating button (bell, more, locate…).
struct GlassCircleButton: View {
    let symbol: String
    let label: String
    var badge = false
    let action: () -> Void

    var body: some View {
        Button { Haptics.light(); action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .alongGlass(in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(AlongColor.lime).frame(width: 11, height: 11).overlay(Circle().stroke(AlongColor.navy, lineWidth: 2)).offset(x: -3, y: 3) }
                }
        }
        .buttonStyle(AlongPressStyle(scale: 0.94))
        .accessibilityLabel(label)
    }
}

// MARK: - Filters

/// All · Today · Tomorrow · 📅. The calendar opens a date picker; a chosen day shows as "Nov 12 ×".
struct ExploreFilterBar: View {
    @Bindable var vm: ExploreViewModel
    @State private var showCalendar = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AlongSpacing.xs) {
                pill("All", selected: vm.dateFilter == .all) { vm.setDate(.all) }
                pill("Today", selected: vm.dateFilter == .today) { vm.setDate(vm.dateFilter == .today ? .all : .today) }
                pill("Tomorrow", selected: vm.dateFilter == .tomorrow) { vm.setDate(vm.dateFilter == .tomorrow ? .all : .tomorrow) }
                if let label = vm.label(for: vm.dateFilter) { customDay(label) } else { calendarButton }
            }
            .padding(.horizontal, AlongSpacing.md)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .sheet(isPresented: $showCalendar) {
            ExploreDateSheet(vm: vm)
                .presentationDetents([.height(520)])
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Text(title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? AlongColor.navy : .white)
                .padding(.horizontal, 16).frame(minHeight: 40)
                .background { if selected { Capsule().fill(.white) } else { Capsule().fill(.clear).alongGlass(tint: 0.5) } }
                .shadow(color: .black.opacity(selected ? 0.2 : 0), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var calendarButton: some View {
        Button { Haptics.selection(); showCalendar = true } label: {
            Image(systemName: "calendar").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .frame(width: 44, height: 40).alongGlass(tint: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick a date")
    }

    private func customDay(_ label: String) -> some View {
        HStack(spacing: 2) {
            Button { Haptics.selection(); showCalendar = true } label: {
                Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(AlongColor.navy)
                    .padding(.leading, 16).frame(minHeight: 40)
            }
            Button { Haptics.selection(); vm.setDate(.all) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(AlongColor.navy.opacity(0.7))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Clear date")
        }
        .background(Capsule().fill(.white))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Showing walks on \(label)")
    }
}

/// A minimal calendar: navy selection on off-white. Picks a New York day from today onward.
struct ExploreDateSheet: View {
    @Bindable var vm: ExploreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(spacing: AlongSpacing.md) {
            Text("Pick a day").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(AlongColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, AlongSpacing.md)
            DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, ExploreViewModel.newYork)
                .environment(\.timeZone, ExploreViewModel.newYork.timeZone)
                .tint(AlongColor.navy)
                .labelsHidden()
            Spacer(minLength: 0)
            HStack(spacing: AlongSpacing.sm) {
                AlongButton(title: "Clear", style: .secondary) { vm.setDate(.all); dismiss() }
                AlongButton(title: "Show walks") { vm.setDate(.day(date)); dismiss() }
            }
        }
        .padding(.horizontal, AlongSpacing.gutter)
        .padding(.bottom, AlongSpacing.md)
        .onAppear { if case .day(let d) = vm.dateFilter { date = d } }
    }
}

// MARK: - Map pins

/// A walk on the map. Zoomed out it is the host's photo (with a "+N" for people going); selected, it grows into a labelled
/// bubble with the title and route. Everything shown is real: the host's profile and the accepted-guest count.
struct ActivityPin: View {
    let activity: Activity
    let host: User?
    var isSelected: Bool

    private var going: Int { activity.participantCount ?? activity.participantIDs.count }
    private var isLive: Bool { activity.startDate <= .now && activity.endDate > .now }

    var body: some View {
        VStack(spacing: 0) {
            if isSelected { bubble } else { avatarPin }
            stem
        }
        .animation(.smooth(duration: 0.28), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk: \(activity.title), \(activity.publicLocationLabel)")
        .accessibilityAddTraits(.isButton)
    }

    private var avatar: some View {
        Group {
            if let host { AlongProfileAvatar(user: host, size: 44) } else { Circle().fill(AlongColor.surface).frame(width: 44, height: 44) }
        }
        .overlay(Circle().stroke(isLive ? AlongColor.lime : .white, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private var avatarPin: some View {
        HStack(spacing: -10) {
            avatar
            if going > 0 {
                Text("+\(going)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(AlongColor.navy)
                    .frame(minWidth: 26, minHeight: 26).padding(.horizontal, 2)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .offset(x: 6, y: -2)
            }
        }
    }

    private var bubble: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(activity.publicLocationLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                if going > 0 { Text("\(host?.firstName ?? "Host") + \(going) going").font(.system(size: 11, weight: .semibold)).foregroundStyle(AlongColor.lime) }
            }
            .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 8)
        .alongGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), tint: 0.7)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.lime.opacity(0.9), lineWidth: 1.5))
    }

    private var stem: some View {
        Capsule().fill(isSelected ? AlongColor.lime : .white).frame(width: 3, height: isSelected ? 14 : 10)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// Several nearby walks, merged while zoomed out. The number is the real count of loaded walks it stands for.
struct ClusterPin: View {
    let count: Int
    var isSelected = false
    var body: some View {
        ZStack {
            Circle().fill(AlongColor.lime.opacity(0.30)).frame(width: 74, height: 74)
            if isSelected { Circle().stroke(AlongColor.navy, lineWidth: 3).frame(width: 66, height: 66) }
            Circle().fill(AlongColor.lime.opacity(0.55)).frame(width: 58, height: 58)
            VStack(spacing: -2) {
                Text("\(count)").font(.system(size: 22, weight: .heavy)).foregroundStyle(AlongColor.navy)
                Text("walks").font(.system(size: 10, weight: .bold)).foregroundStyle(AlongColor.navy.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) walks")
        .accessibilityHint("Shows these walks")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Floating tab bar

struct FloatingTabBar: View {
    @Binding var selection: Int
    var badge = 0
    let onCreate: () -> Void

    private let tabs: [(symbol: String, title: String)] = [
        ("mappin.and.ellipse", "Explore"), ("figure.walk", "Walks"), ("bubble.left", "Messages"), ("person", "Profile"),
    ]

    var body: some View {
        HStack(spacing: AlongSpacing.sm) {
            HStack(spacing: 2) {
                ForEach(tabs.indices, id: \.self) { i in tab(i) }
            }
            .padding(5)
            .alongGlass(tint: 0.62)

            Button { Haptics.light(); onCreate() } label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(AlongColor.navy)
                    .frame(width: 58, height: 58)
                    .background(AlongColor.lime, in: Circle())
                    .shadow(color: AlongColor.lime.opacity(0.45), radius: 12, y: 4)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(AlongPressStyle(scale: 0.94))
            .accessibilityLabel("Create a walk")
        }
        .padding(.horizontal, AlongSpacing.md)
    }

    private func tab(_ i: Int) -> some View {
        let selected = selection == i
        return Button { if selection != i { alongWithAnimation(.smooth(duration: 0.25)) { selection = i } } } label: {
            VStack(spacing: 2) {
                Image(systemName: tabs[i].symbol).font(.system(size: 18, weight: .semibold))
                Text(tabs[i].title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? AlongColor.navy : .white.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { if selected { Capsule().fill(.white) } }
            .overlay(alignment: .topTrailing) {
                if i == 2, badge > 0 {
                    Circle().fill(AlongColor.lime).frame(width: 11, height: 11).overlay(Circle().stroke(AlongColor.navy, lineWidth: 2)).offset(x: -16, y: 4)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tabs[i].title + (i == 2 && badge > 0 ? ", \(badge) new" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lets the Explore screen hide the floating tab bar while a walk card is open.
@MainActor @Observable
final class TabChrome {
    var isHidden = false
    /// Open conversations (a counter, so overlapping appear/disappear during a push can't strand the bar hidden).
    private var openChats = 0
    var chatOpen: Bool { openChats > 0 }
    func chatAppeared() { openChats += 1 }
    func chatDisappeared() { openChats = max(0, openChats - 1) }
}
