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

/// Realistic New York City demo data (every borough). Dates are generated relative to *now*, so the map never goes stale.
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
            User(id: "me", firstName: "Göksu", bio: "Software engineer. Usually walking somewhere, usually thinking too much.",
                 hobbies: ["Technology", "Coffee", "Startups", "Walking"], avatarTone: 0, age: 29, occupation: "Software engineer", languages: ["English", "Turkish"], instagram: "goksu", xHandle: "goksu", pacePreference: .casual, preferredDuration: 45, favoriteNeighborhoods: ["Upper West Side", "Chelsea"], discussionTopics: [.career, .existential], conversationCustom: ["Building things"]),
            User(id: "alex", firstName: "Alex", bio: "Building a startup in SoHo. Walks to clear my head.",
                 hobbies: ["Startups", "Technology", "Coffee"], avatarTone: 1),
            User(id: "emma", firstName: "Emma", bio: "Product designer. Walks home through the park most evenings.",
                 hobbies: ["Design", "Art", "Walking", "Literature"], avatarTone: 2, age: 31, occupation: "Product designer", languages: ["English", "French"], instagram: "emma.walks", pacePreference: .moderate, preferredDuration: 30, favoriteNeighborhoods: ["Upper West Side", "Midtown"], discussionTopics: [.career, .relationships]),
            User(id: "daniel", firstName: "Daniel", bio: "Writer, mostly. Always up for a long walk and a better cup of coffee.",
                 hobbies: ["Literature", "Walking", "Coffee"], avatarTone: 3),
            User(id: "priya", firstName: "Priya", bio: "Data scientist. Trying to hit 10k steps without trying.",
                 hobbies: ["Technology", "Gym", "Walking"], avatarTone: 4),
            User(id: "maya", firstName: "Maya", bio: "Illustrator and Chelsea regular. Gallery walks are my favourite kind.",
                 hobbies: ["Art", "Design", "Walking"], avatarTone: 5),
            User(id: "jonas", firstName: "Jonas", bio: "Architect. Early riser, Central Park loop enthusiast.",
                 hobbies: ["Design", "Gym", "Walking"], avatarTone: 0),
            User(id: "sofia", firstName: "Sofia", bio: "Freelance marketer. Best ideas show up mid-walk.",
                 hobbies: ["Coffee", "Startups", "Literature"], avatarTone: 1),
            User(id: "marcus", firstName: "Marcus", bio: "Indie developer. Happy to talk it through or just walk.",
                 hobbies: ["Technology", "Startups", "Coffee"], avatarTone: 2),
        ]

        func street(_ n: Int) -> Place { NYCGeo.street(n) }
        func landmark(_ name: String) -> Place { NYCGeo.landmarks.first { $0.name == name }! }
        func spot(_ name: String, _ lat: Double, _ lng: Double) -> Place {
            Place(name: name, area: NYCGeo.neighborhood(near: Coordinate(lat, lng)), coordinate: Coordinate(lat, lng), isStreet: true)
        }
        let brooklynWalk = slot(day: 0, 19, 0, minutes: 60), queensWalk = slot(day: 1, 10, 0, minutes: 75)
        let bronxWalk = slot(day: 1, 16, 30, minutes: 60), statenWalk = slot(day: 2, 11, 0, minutes: 90), crossWalk = slot(day: 0, 18, 0, minutes: 60)

        // MARK: Activities
        let midtown = slot(day: 0, 17, 0, minutes: 60)
        let chelsea = slot(day: 0, 18, 30, minutes: 45)
        let park = slot(day: 1, 9, 0, minutes: 75)
        let east = slot(day: 1, 18, 0, minutes: 60)
        let battery = slot(day: 2, 8, 0, minutes: 90)
        let careers = slot(day: 0, 17, 30, minutes: 60)
        let lately = slot(day: 1, 19, 0, minutes: 75)
        let thinking = slot(day: 2, 18, 0, minutes: 60)

        db.activities = [
            Activity(id: "act-midtown", title: "Evening walk to Midtown", hostID: "me",
                     walk: WalkInfo(from: street(72), to: street(55), pace: .casual),
                     startDate: midtown.0, endDate: midtown.1, visibility: .public, capacity: 2, participantIDs: ["priya"],
                     note: "Getting my steps in after work. Feel free to join!",
                     meetingDetails: "I'll be at the south-west corner of 72nd & Broadway, by the subway steps, in a navy jacket."),
            Activity(id: "act-chelsea", title: "Quick walk through Chelsea", hostID: "maya",
                     walk: WalkInfo(from: street(23), to: street(14), pace: .moderate),
                     startDate: chelsea.0, endDate: chelsea.1, visibility: .public, capacity: 3,
                     note: "A brisk gallery loop if the weather holds.",
                     meetingDetails: "Meet outside the 23rd St C/E entrance on 8th Avenue."),
            Activity(id: "act-park", title: "Morning Central Park walk", hostID: "jonas",
                     walk: WalkInfo(from: landmark("Central Park West"), to: landmark("Columbus Circle"), pace: .casual),
                     startDate: park.0, endDate: park.1, visibility: .public, capacity: 3, participantIDs: ["me"],
                     note: "Easy pace along the west side, coffee after.",
                     meetingDetails: "Meet at the Strawberry Fields entrance, W 72nd & Central Park West."),
            Activity(id: "act-east", title: "Evening stroll along the East Side", hostID: "daniel",
                     walk: WalkInfo(from: street(79), to: street(96), pace: .casual),
                     startDate: east.0, endDate: east.1, visibility: .public, capacity: 2,
                     note: "Unwinding after a long writing day. Conversation optional.",
                     meetingDetails: "By the river entrance of Carl Schurz Park."),
            Activity(id: "act-battery", title: "Walk down to the Battery", hostID: "emma",
                     walk: WalkInfo(from: landmark("Washington Square Park"), to: landmark("Battery Park"), pace: .moderate),
                     startDate: battery.0, endDate: battery.1, visibility: .public, capacity: 3,
                     note: "Heading downtown before work. Moderate pace.",
                     meetingDetails: "Meet at the north end of Washington Square Park, by the arch."),
            Activity(id: "act-careers", title: "Let's overthink our careers.", hostID: "emma",
                     walk: WalkInfo(from: street(72), to: landmark("Columbus Circle"), pace: .casual),
                     startDate: careers.0, endDate: careers.1, visibility: .public, capacity: 2,
                     note: "Weighing up a big decision. Bring your hot takes.",
                     meetingDetails: "West 72nd & Broadway, by the subway steps.", mindPrompt: "Career stuff, honestly. Changing teams."),
            Activity(id: "act-lately", title: "Life lately, out loud", hostID: "daniel",
                     walk: WalkInfo(from: street(79), to: street(96), pace: .casual),
                     startDate: lately.0, endDate: lately.1, visibility: .public, capacity: 2,
                     note: "No agenda. Just say what's on your mind.",
                     meetingDetails: "River entrance of Carl Schurz Park.", hostAnonymous: true,
                     hostInterests: ["Literature", "Philosophy", "Coffee"], mindPrompt: "Life lately."),
            Activity(id: "act-random", title: "Random thoughts along the park", hostID: "priya",
                     walk: WalkInfo(from: landmark("Washington Square Park"), to: landmark("Union Square"), pace: .moderate),
                     startDate: thinking.0, endDate: thinking.1, visibility: .public, capacity: 3,
                     note: "Distract me with your weirdest question.",
                     meetingDetails: "North end of Washington Square Park.", mindPrompt: "Random thoughts, mostly."),
            // The other boroughs, and one that crosses the East River.
            Activity(id: "act-brooklyn", title: "Prospect Park loop", hostID: "sofia",
                     walk: WalkInfo(from: landmark("Prospect Park (Brooklyn)"), to: landmark("Brooklyn Botanic Garden"), pace: .casual),
                     startDate: brooklynWalk.0, endDate: brooklynWalk.1, visibility: .public, capacity: 3,
                     note: "An easy loop before dinner.", meetingDetails: "Grand Army Plaza arch, park side.", mindPrompt: "Trying to decide whether to move."),
            Activity(id: "act-queens", title: "Astoria Park to the waterfront", hostID: "marcus",
                     walk: WalkInfo(from: landmark("Astoria Park"), to: landmark("Gantry Plaza State Park"), pace: .moderate),
                     startDate: queensWalk.0, endDate: queensWalk.1, visibility: .public, capacity: 2,
                     note: "Skyline views the whole way.", meetingDetails: "By the Astoria Park pool entrance."),
            Activity(id: "act-bronx", title: "Fordham to the Botanical Garden", hostID: "daniel",
                     walk: WalkInfo(from: spot("Fordham Road", 40.8610, -73.8900), to: landmark("New York Botanical Garden"), pace: .casual),
                     startDate: bronxWalk.0, endDate: bronxWalk.1, visibility: .public, capacity: 2,
                     note: "Slow, green and quiet.", meetingDetails: "Outside the Fordham Metro-North station."),
            Activity(id: "act-staten", title: "Ferry terminal to Snug Harbor", hostID: "priya",
                     walk: WalkInfo(from: landmark("Staten Island Ferry Terminal"), to: landmark("Snug Harbor Cultural Center"), pace: .casual),
                     startDate: statenWalk.0, endDate: statenWalk.1, visibility: .public, capacity: 3,
                     note: "Arrive on the ferry, walk the north shore.", meetingDetails: "Outside the St. George terminal doors."),
            Activity(id: "act-cross", title: "Across the Williamsburg Bridge", hostID: "emma",
                     walk: WalkInfo(from: landmark("Domino Park"), to: landmark("Tompkins Square Park"), pace: .moderate),
                     startDate: crossWalk.0, endDate: crossWalk.1, visibility: .public, capacity: 2,
                     note: "Brooklyn to the Lower East Side on foot.", meetingDetails: "Domino Park, by the sugar refinery sign."),
        ]

        // Yesterday, for the Past tab.
        let ps = date(day: -1, 8, 30)
        db.activities += [
            Activity(id: "act-past-walk", title: "Morning walk to Union Square", hostID: "me",
                     walk: WalkInfo(from: landmark("Washington Square Park"), to: landmark("Union Square"), pace: .casual),
                     startDate: ps, endDate: ps.addingTimeInterval(3600), visibility: .public, capacity: 2, participantIDs: ["priya"],
                     note: "Easy start to the day.", meetingDetails: "By the fountain."),
        ]

        // MARK: Requests
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        db.requests = [
            JoinRequest(id: "req-emma", activityID: "act-midtown", requesterID: "emma", status: .pending, createdAt: ago(42)),
            JoinRequest(id: "req-daniel", activityID: "act-midtown", requesterID: "daniel", status: .pending, createdAt: ago(18)),
            JoinRequest(id: "req-priya", activityID: "act-midtown", requesterID: "priya", status: .accepted, createdAt: ago(300)),
            JoinRequest(id: "req-me-park", activityID: "act-park", requesterID: "me", status: .accepted, createdAt: ago(600)),
            JoinRequest(id: "req-me-careers", activityID: "act-careers", requesterID: "me", status: .pending, createdAt: ago(25)),
            JoinRequest(id: "req-past-priya", activityID: "act-past-walk", requesterID: "priya", status: .accepted, createdAt: ago(2000)),
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
