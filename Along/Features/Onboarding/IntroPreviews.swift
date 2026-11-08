import SwiftUI

// Static, non-interactive pictures for the first-launch tutorial. Nothing here talks to MapKit, Supabase or location:
// the "maps" are drawn, the people and numbers are labelled examples, and no button does anything.

/// A drawn, dark, aerial-looking street map. One `Canvas`, no tiles, no network.
struct IntroMapBackdrop: View {
    var rotation: Double = -29
    var seed = 0

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x1E2430)))
            // water, bottom-left and right edge
            var water = Path()
            water.move(to: .init(x: 0, y: size.height * 0.55))
            water.addCurve(to: .init(x: size.width * 0.22, y: size.height), control1: .init(x: size.width * 0.12, y: size.height * 0.62), control2: .init(x: size.width * 0.12, y: size.height * 0.9))
            water.addLine(to: .init(x: 0, y: size.height)); water.closeSubpath()
            ctx.fill(water, with: .color(Color(hex: 0x182A3A)))
            // park
            let park = Path(roundedRect: CGRect(x: size.width * (0.40 + Double(seed % 3) * 0.04), y: size.height * 0.18, width: size.width * 0.18, height: size.height * 0.55), cornerRadius: 6)
            ctx.fill(park, with: .color(Color(hex: 0x24402F)))
            // street grid, rotated like Manhattan's
            var grid = ctx
            grid.translateBy(x: size.width / 2, y: size.height / 2)
            grid.rotate(by: .degrees(rotation))
            let span = max(size.width, size.height) * 1.4
            var streets = Path()
            var x = -span
            while x < span { streets.move(to: .init(x: x, y: -span)); streets.addLine(to: .init(x: x, y: span)); x += 15 }
            var y = -span
            while y < span { streets.move(to: .init(x: -span, y: y)); streets.addLine(to: .init(x: span, y: y)); y += 9 }
            grid.stroke(streets, with: .color(.white.opacity(0.07)), lineWidth: 0.8)
            var avenues = Path()
            x = -span
            while x < span { avenues.move(to: .init(x: x, y: -span)); avenues.addLine(to: .init(x: x, y: span)); x += 60 }
            grid.stroke(avenues, with: .color(.white.opacity(0.13)), lineWidth: 1.6)
        }
        .accessibilityHidden(true)
    }
}

private struct ExampleTag: View {
    var body: some View {
        Text("EXAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.8)
            .foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 7).padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
    }
}

private struct PinDot: View {
    let initial: String
    var body: some View {
        VStack(spacing: 0) {
            Text(initial).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(AlongColor.navy)
                .frame(width: 40, height: 40).background(AlongColor.offWhite, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
            Capsule().fill(AlongColor.offWhite).frame(width: 3, height: 7)
        }
    }
}

private func glassPill(_ symbol: String?, _ text: String, selected: Bool = false) -> some View {
    HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
        Text(text).font(.system(size: 13, weight: .semibold))
    }
    .foregroundStyle(selected ? AlongColor.navy : .white)
    .padding(.horizontal, 12).frame(height: 32)
    .background(selected ? AnyShapeStyle(AlongColor.offWhite) : AnyShapeStyle(.white.opacity(0.18)), in: Capsule())
}

/// Screen 2: pins, a numbered cluster, and the filter row.
struct IntroExplorePreview: View {
    var body: some View {
        ZStack {
            IntroMapBackdrop(seed: 0)
            GeometryReader { g in
                PinDot(initial: "M").position(x: g.size.width * 0.30, y: g.size.height * 0.40)
                PinDot(initial: "S").position(x: g.size.width * 0.52, y: g.size.height * 0.62)
                ClusterPin(count: 2).scaleEffect(0.9).position(x: g.size.width * 0.74, y: g.size.height * 0.46)
            }
            VStack {
                HStack(spacing: 6) {
                    AlongLogo(variant: .white, width: 62)
                    Spacer()
                    glassPill(nil, "All", selected: true); glassPill(nil, "Today"); glassPill(nil, "Tomorrow")
                }
                .padding(10)
                Spacer()
                HStack { Spacer(); ExampleTag() }.padding(10)
            }
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example map with walking pins and a cluster of two walks")
    }
}

/// Screen 3: the route search bar with the date filters.
struct IntroRoutePreview: View {
    var body: some View {
        ZStack {
            IntroMapBackdrop(seed: 1)
            // an example route
            Path { p in
                p.move(to: .init(x: 70, y: 210)); p.addCurve(to: .init(x: 270, y: 130), control1: .init(x: 130, y: 200), control2: .init(x: 190, y: 120))
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            Path { p in
                p.move(to: .init(x: 70, y: 210)); p.addCurve(to: .init(x: 270, y: 130), control1: .init(x: 130, y: 200), control2: .init(x: 190, y: 120))
            }
            .stroke(AlongColor.navy, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    glassPill(nil, "All", selected: true); glassPill(nil, "Today"); glassPill(nil, "Tomorrow")
                    glassPill("calendar", "").frame(width: 40)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 14, weight: .semibold))
                    Text("West Village → Bryant Park").font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 44)
                .background(.ultraThinMaterial, in: Capsule()).background(AlongColor.navy.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(AlongColor.lime, lineWidth: 2))
                .shadow(color: AlongColor.lime.opacity(0.5), radius: 10)
                Spacer()
                HStack { Spacer(); ExampleTag() }
            }
            .padding(10)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example route search from West Village to Bryant Park with Today, Tomorrow and calendar filters")
    }
}

/// Screen 4: the real floating tab bar with its Create button, drawn over a map.
struct IntroCreatePreview: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            IntroMapBackdrop(seed: 2)
            FloatingTabBar(selection: .constant(0), badge: 0, onCreate: {})
                .allowsHitTesting(false)
                .scaleEffect(0.82).padding(.bottom, 8)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Screen 5: a walk card like the one that opens from the map, with a labelled example.
struct IntroWalkCardPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) { Image(systemName: "figure.walk").font(.system(size: 11, weight: .semibold)); Text("Walk").font(AlongFont.label) }
                    .foregroundStyle(AlongColor.navy).padding(.horizontal, 10).padding(.vertical, 5).background(AlongColor.surface, in: Capsule())
                Spacer()
                Text("EXAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(AlongColor.textTertiary)
            }
            Text("Morning walk to Upper West Side").font(AlongFont.walkCardTitle).foregroundStyle(AlongColor.navy)
            HStack(spacing: 8) { Image(systemName: "person").frame(width: 20); Text("Hosted by a neighbor").font(AlongFont.subhead) }
            HStack(spacing: 8) { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").frame(width: 20); Text("72nd St → Upper West Side").font(AlongFont.subhead) }
            HStack(spacing: 8) { Image(systemName: "calendar").frame(width: 20); Text("Tomorrow, 9:00 AM").font(AlongFont.subhead) }
            HStack(spacing: AlongSpacing.xs) {
                Image(systemName: "figure.walk").font(.system(size: 15, weight: .semibold))
                Text("Request to Join").font(AlongFont.bodyEmphasis)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 52)
            .background(AlongColor.navy, in: Capsule())
            .overlay(Capsule().stroke(AlongColor.lime, lineWidth: 2).padding(-4))
        }
        .foregroundStyle(AlongColor.textPrimary)
        .padding(AlongSpacing.md)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example walk card with a Request to Join button")
    }
}

/// Screen 6: two avatars on a route. Drawn only; nothing is tracked.
struct IntroLiveWalkPreview: View {
    var body: some View {
        ZStack {
            IntroMapBackdrop(rotation: -20, seed: 1)
            Path { p in
                p.move(to: .init(x: 60, y: 215)); p.addCurve(to: .init(x: 280, y: 60), control1: .init(x: 150, y: 230), control2: .init(x: 180, y: 70))
            }
            .stroke(AlongColor.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .shadow(color: AlongColor.lime.opacity(0.6), radius: 8)
            Circle().fill(AlongColor.offWhite).frame(width: 46, height: 46).overlay(Text("A").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(AlongColor.navy))
                .overlay(Circle().stroke(.white, lineWidth: 2.5)).shadow(radius: 5).position(x: 60, y: 215)
            Circle().fill(AlongColor.lime).frame(width: 46, height: 46).overlay(Text("B").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(AlongColor.navy))
                .overlay(Circle().stroke(.white, lineWidth: 2.5)).shadow(radius: 5).position(x: 280, y: 60)
            VStack {
                HStack {
                    HStack(spacing: 6) { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 12, weight: .semibold)); Text("Live Walk").font(.system(size: 13, weight: .semibold)) }
                        .foregroundStyle(AlongColor.lime).padding(.horizontal, 12).frame(height: 32)
                        .background(AlongColor.navy.opacity(0.85), in: Capsule()).overlay(Capsule().stroke(AlongColor.lime, lineWidth: 1.5))
                    Spacer(); ExampleTag()
                }
                Spacer()
                HStack {
                    HStack(spacing: 8) { Text("32:14").font(.system(size: 15, weight: .semibold).monospacedDigit()); Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 16); Text("1.6 mi").font(.system(size: 15, weight: .semibold)) }
                        .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 38)
                        .background(.ultraThinMaterial, in: Capsule()).background(AlongColor.navy.opacity(0.6), in: Capsule())
                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example live walk: two walkers on a highlighted route")
    }
}

/// Screen 7: a profile with stats, plus a past walk.
struct IntroMemoriesPreview: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Circle().fill(AlongColor.surface).frame(width: 54, height: 54).overlay(AlongMark(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your name").font(AlongFont.walkCardTitle).foregroundStyle(AlongColor.navy)
                        Text("NYC · Walking, coffee, overthinking").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                    Spacer()
                    Text("EXAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(AlongColor.textTertiary)
                }
                HStack {
                    stat("24", "Walks"); Divider().frame(height: 30); stat("6.4 mi", "This month"); Divider().frame(height: 30); stat("12", "People")
                }
            }
            .padding(AlongSpacing.md)
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AlongColor.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Text("Past Walks").font(AlongRoboto.bold(17, relativeTo: .headline)).foregroundStyle(AlongColor.navy)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1E2430)).frame(width: 54, height: 54)
                        .overlay(IntroMapBackdrop(seed: 2).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("West Village → SoHo").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.navy)
                        Text("28 min · 1.3 mi").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
                }
            }
            .padding(AlongSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example profile with walking statistics and a past walk")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(AlongRoboto.bold(18, relativeTo: .headline)).foregroundStyle(AlongColor.navy).minimumScaleFactor(0.8).lineLimit(1)
            Text(label).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
