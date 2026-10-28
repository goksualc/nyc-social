import Foundation

/// In-memory "database" used by the mock backend.
struct MockDatabase: Sendable {
    var meID: ID = "me"
    var settings = UserSettings()
    var users: [User] = []
    var activities: [Activity] = []
    var requests: [JoinRequest] = []
    var conversations: [Conversation] = []
    var messages: [Message] = []
    var blocked: Set<ID> = []
    var reports: [String] = []
}

/// Realistic Manhattan demo data. Dates are generated relative to *now*, so the map never goes stale.
enum SeedData {
    static func make(now: Date, calendar: Calendar = .current) -> MockDatabase {
        var db = MockDatabase()

        func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        /// Today's slots that have already passed slide forward so there's always something to join.
        func slot(day: Int, _ hour: Int, _ minute: Int = 0, minutes: Int) -> (Date, Date) {
            var start = date(day: day, hour, minute)
            var end = start.addingTimeInterval(Double(minutes) * 60)
            if day == 0, end <= now.addingTimeInterval(45 * 60) {
                let soon = now.addingTimeInterval(40 * 60)
                let m = calendar.component(.minute, from: soon)
                start = calendar.date(byAdding: .minute, value: m <= 30 ? 30 - m : 60 - m, to: soon)!
                start = calendar.date(bySetting: .second, value: 0, of: start)!
                end = start.addingTimeInterval(Double(minutes) * 60)
            }
            return (start, end)
        }
        func nextFriday(atLeast days: Int) -> Int {
            var d = days
            while calendar.component(.weekday, from: calendar.date(byAdding: .day, value: d, to: now)!) != 6 { d += 1 }
            return d
        }

        // MARK: People
        db.users = [
            User(id: "me", firstName: "Göksu", bio: "Software engineer. Usually walking somewhere or working from a café.",
                 interests: [.tech, .coffee, .startups, .walking], alongFor: [.walkingBuddies, .coworkingCompany], avatarTone: 0),
            User(id: "alex", firstName: "Alex", bio: "Building a startup in SoHo. Strong coffee, quiet focus.",
                 interests: [.startups, .tech, .coffee], alongFor: [.coworkingCompany], avatarTone: 1),
            User(id: "emma", firstName: "Emma", bio: "Product designer. Walks home through the park most evenings.",
                 interests: [.design, .art, .walking, .books], alongFor: [.walkingBuddies, .coworkingCompany], avatarTone: 2),
            User(id: "daniel", firstName: "Daniel", bio: "Writer, mostly. Always up for a long walk and a better cup of coffee.",
                 interests: [.books, .walking, .coffee], alongFor: [.walkingBuddies, .coworkingCompany], avatarTone: 3),
            User(id: "priya", firstName: "Priya", bio: "Data scientist. Trying to hit 10k steps without trying.",
                 interests: [.tech, .fitness, .walking], alongFor: [.walkingBuddies], avatarTone: 4),
            User(id: "maya", firstName: "Maya", bio: "Illustrator and Chelsea regular. Gallery walks are my favourite kind.",
                 interests: [.art, .design, .walking], alongFor: [.walkingBuddies], avatarTone: 5),
            User(id: "jonas", firstName: "Jonas", bio: "Architect. Early riser, Central Park loop enthusiast.",
                 interests: [.design, .fitness, .walking], alongFor: [.walkingBuddies], avatarTone: 0),
            User(id: "sofia", firstName: "Sofia", bio: "Freelance marketer. Social coworking beats lonely coworking.",
                 interests: [.coffee, .startups, .books], alongFor: [.coworkingCompany], avatarTone: 1),
            User(id: "marcus", firstName: "Marcus", bio: "Indie developer working on something new. Happy to pair or sit quietly.",
                 interests: [.tech, .startups, .coffee], alongFor: [.coworkingCompany], avatarTone: 2),
        ]

        func street(_ n: Int) -> Place { ManhattanGeo.street(n) }
        func landmark(_ name: String) -> Place { ManhattanGeo.landmarks.first { $0.name == name }! }
        func cafe(_ name: String) -> Place { ManhattanGeo.cafes.first { $0.name == name }! }

        // MARK: Activities
        let midtown = slot(day: 0, 17, 0, minutes: 60)
        let chelsea = slot(day: 0, 18, 30, minutes: 45)
        let flatiron = slot(day: 0, 14, 0, minutes: 180)
        let park = slot(day: 1, 9, 0, minutes: 75)
        let soho = slot(day: 1, 13, 0, minutes: 240)
        let east = slot(day: 1, 18, 0, minutes: 60)
        let village = slot(day: 1, 10, 0, minutes: 120)
        let fri = nextFriday(atLeast: 2)
        let building = slot(day: fri, 11, 0, minutes: 240)
        let battery = slot(day: 2, 8, 0, minutes: 90)

        db.activities = [
            Activity(id: "act-midtown", title: "Evening walk to Midtown", hostID: "me",
                     details: .walk(WalkInfo(from: street(72), to: street(55), pace: .casual)),
                     startDate: midtown.0, endDate: midtown.1, visibility: .public, capacity: 2, participantIDs: ["priya"],
                     note: "Getting my steps in after work. Feel free to join!",
                     meetingDetails: "I'll be at the south-west corner of 72nd & Broadway, by the subway steps, in a navy jacket."),
            Activity(id: "act-chelsea", title: "Quick walk through Chelsea", hostID: "maya",
                     details: .walk(WalkInfo(from: street(23), to: street(14), pace: .moderate)),
                     startDate: chelsea.0, endDate: chelsea.1, visibility: .public, capacity: 3,
                     note: "A brisk gallery loop if the weather holds.",
                     meetingDetails: "Meet outside the 23rd St C/E entrance on 8th Avenue."),
            Activity(id: "act-park", title: "Morning Central Park walk", hostID: "jonas",
                     details: .walk(WalkInfo(from: landmark("Central Park West"), to: landmark("Columbus Circle"), pace: .casual)),
                     startDate: park.0, endDate: park.1, visibility: .public, capacity: 3, participantIDs: ["me"],
                     note: "Easy pace along the west side, coffee after.",
                     meetingDetails: "Meet at the Strawberry Fields entrance, W 72nd & Central Park West."),
            Activity(id: "act-east", title: "Evening stroll along the East Side", hostID: "daniel",
                     details: .walk(WalkInfo(from: street(79), to: street(96), pace: .casual)),
                     startDate: east.0, endDate: east.1, visibility: .public, capacity: 2,
                     note: "Unwinding after a long writing day. Conversation optional.",
                     meetingDetails: "By the river entrance of Carl Schurz Park."),
            Activity(id: "act-battery", title: "Walk down to the Battery", hostID: "emma",
                     details: .walk(WalkInfo(from: landmark("Washington Square Park"), to: landmark("Battery Park"), pace: .moderate)),
                     startDate: battery.0, endDate: battery.1, visibility: .public, capacity: 3,
                     note: "Heading downtown before work. Moderate pace.",
                     meetingDetails: "Meet at the north end of Washington Square Park, by the arch."),
            Activity(id: "act-soho", title: "Working from SoHo", hostID: "alex",
                     details: .cowork(CoworkInfo(venue: cafe("Lantern Coffee"), style: .deepWork)),
                     startDate: soho.0, endDate: soho.1, visibility: .public, capacity: 2,
                     note: "Working on my startup. Happy to have some company.",
                     meetingDetails: "Lantern Coffee — I'll have the big table by the window."),
            Activity(id: "act-flatiron", title: "Coffee & coworking", hostID: "sofia",
                     details: .cowork(CoworkInfo(venue: cafe("Sidecar Espresso"), style: .social)),
                     startDate: flatiron.0, endDate: flatiron.1, visibility: .public, capacity: 3,
                     note: "Emails, calls and a lot of coffee. Chatty table.",
                     meetingDetails: "Sidecar Espresso — look for the green laptop sleeve."),
            Activity(id: "act-westvillage", title: "Building something new", hostID: "marcus",
                     details: .cowork(CoworkInfo(venue: cafe("Marlow Roasters"), style: .buildTogether)),
                     startDate: building.0, endDate: building.1, visibility: .public, capacity: 2,
                     note: "Heads-down building. Bring your laptop and whatever you're stuck on.",
                     meetingDetails: "Marlow Roasters — back corner, two seats by the outlets."),
            Activity(id: "act-eastvillage", title: "Reading & writing hour", hostID: "daniel",
                     details: .cowork(CoworkInfo(venue: cafe("Kettle Row"), style: .deepWork)),
                     startDate: village.0, endDate: village.1, visibility: .public, capacity: 3,
                     note: "Quiet table, notebooks out.",
                     meetingDetails: "Kettle Row — upstairs if it's busy."),
        ]

        // Yesterday, for the Past tab.
        let ps = date(day: -1, 8, 30)
        let cs = date(day: -1, 10, 0)
        db.activities += [
            Activity(id: "act-past-walk", title: "Morning walk to Union Square", hostID: "me",
                     details: .walk(WalkInfo(from: landmark("Washington Square Park"), to: landmark("Union Square"), pace: .casual)),
                     startDate: ps, endDate: ps.addingTimeInterval(3600), visibility: .public, capacity: 2, participantIDs: ["priya"],
                     note: "Easy start to the day.", meetingDetails: "By the fountain."),
            Activity(id: "act-past-cowork", title: "Coffee & coworking", hostID: "sofia",
                     details: .cowork(CoworkInfo(venue: cafe("Sidecar Espresso"), style: .social)),
                     startDate: cs, endDate: cs.addingTimeInterval(3 * 3600), visibility: .public, capacity: 3, participantIDs: ["me"],
                     note: "", meetingDetails: "Front window table."),
        ]

        // MARK: Requests
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        db.requests = [
            JoinRequest(id: "req-emma", activityID: "act-midtown", requesterID: "emma", status: .pending, createdAt: ago(42)),
            JoinRequest(id: "req-daniel", activityID: "act-midtown", requesterID: "daniel", status: .pending, createdAt: ago(18)),
            JoinRequest(id: "req-priya", activityID: "act-midtown", requesterID: "priya", status: .accepted, createdAt: ago(300)),
            JoinRequest(id: "req-me-park", activityID: "act-park", requesterID: "me", status: .accepted, createdAt: ago(600)),
            JoinRequest(id: "req-me-soho", activityID: "act-soho", requesterID: "me", status: .pending, createdAt: ago(25)),
            JoinRequest(id: "req-past-priya", activityID: "act-past-walk", requesterID: "priya", status: .accepted, createdAt: ago(2000)),
            JoinRequest(id: "req-past-me", activityID: "act-past-cowork", requesterID: "me", status: .accepted, createdAt: ago(2100)),
        ]

        // MARK: Conversations
        db.conversations = [
            Conversation(id: "conv-priya", activityID: "act-midtown", participantIDs: ["me", "priya"], createdAt: ago(290)),
            Conversation(id: "conv-jonas", activityID: "act-park", participantIDs: ["me", "jonas"], createdAt: ago(590)),
        ]
        db.messages = [
            Message(id: "m1", conversationID: "conv-priya", senderID: "priya", text: "Hi! Thanks for letting me tag along tonight.", sentAt: ago(288)),
            Message(id: "m2", conversationID: "conv-priya", senderID: "me", text: "Of course. I'll be a few minutes early at the subway steps.", sentAt: ago(270)),
            Message(id: "m3", conversationID: "conv-priya", senderID: "priya", text: "Perfect, see you at five.", sentAt: ago(262)),
            Message(id: "m4", conversationID: "conv-jonas", senderID: "jonas", text: "Glad you can join. It's an easy pace, and we'll grab coffee at Columbus Circle after.", sentAt: ago(580)),
            Message(id: "m5", conversationID: "conv-jonas", senderID: "me", text: "Sounds great. Looking forward to it.", sentAt: ago(560)),
        ]
        return db
    }
}
