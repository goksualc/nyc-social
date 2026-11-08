import SwiftUI

/// Hosts can change when, how many, and the notes. Places can't move once people have asked to join.
struct EditActivitySheet: View {
    let activity: Activity
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var duration: TimeInterval
    @State private var spots: Int
    @State private var note: String
    @State private var meeting: String
    @State private var isSaving = false

    init(activity: Activity) {
        self.activity = activity
        _start = State(initialValue: activity.startDate)
        _duration = State(initialValue: activity.endDate.timeIntervalSince(activity.startDate))
        _spots = State(initialValue: activity.capacity)
        _note = State(initialValue: activity.note)
        _meeting = State(initialValue: activity.meetingDetails)
    }

    private var minimumSpots: Int { max(activity.participantIDs.count, activity.participantCount ?? 0, 1) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    Text(activity.title).font(AlongFont.walkScreenHeading).foregroundStyle(AlongColor.textPrimary)
                    Text(activity.publicLocationLabel).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)

                    WhenField(label: "When", date: $start)
                    OptionField(label: "Spots", options: ["1", "2", "3", "4", "5"],
                                selection: Binding(get: { spots - 1 }, set: { spots = max($0 + 1, minimumSpots) }))
                    if minimumSpots > 1 {
                        Text("\(minimumSpots) people are already in, so spots can't go lower.")
                            .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                    AlongTextField(label: "A little note", text: $note,
                                   prompt: "Optional", axis: .vertical, lines: 1...3, limit: 140)
                    AlongTextField(label: "Meeting spot", text: $meeting, prompt: "Shared only with accepted guests",
                                   axis: .vertical, lines: 1...3, limit: 140)
                    Text("Guests are notified when you change the time.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
                .padding(AlongSpacing.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .alongScreenBackground()
            .navigationTitle("Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AlongButton(title: "Save changes", isLoading: isSaving) { Task { await save() } }
                    .padding(.horizontal, AlongSpacing.gutter).padding(.vertical, AlongSpacing.sm)
                    .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
            }
        }
        .alongToasts()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let edit = ActivityEdit(
            activityID: activity.id,
            startDate: start != activity.startDate || duration != activity.endDate.timeIntervalSince(activity.startDate) ? start : nil,
            endDate: start.addingTimeInterval(duration) != activity.endDate ? start.addingTimeInterval(duration) : nil,
            capacity: spots != activity.capacity ? spots : nil,
            note: note != activity.note ? note.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            meetingDetails: meeting != activity.meetingDetails ? meeting.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        if await store.edit(edit) { dismiss() }
    }
}
