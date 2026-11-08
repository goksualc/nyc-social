import SwiftUI
import MapKit

/// The common top of the Profile, Walks and Inbox screens: the Along logo, an optional row of small round buttons, then a
/// large title and one line of supporting text.
struct AlongScreenHeader<Trailing: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack {
                AlongLogo(variant: .navy, width: 104)
                Spacer()
                trailing
            }
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AlongFont.screenHeading).foregroundStyle(AlongColor.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle { Text(subtitle).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary) }
                }
            }
        }
    }
}

extension AlongScreenHeader where Trailing == EmptyView {
    init(title: String? = nil, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// Small round white button for the header (settings, etc.).
struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button { Haptics.light(); action() } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(AlongColor.navy)
                .frame(width: 44, height: 44).background(AlongColor.white, in: Circle())
                .overlay(Circle().stroke(AlongColor.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(AlongPressStyle(scale: 0.94))
        .accessibilityLabel(label)
    }
}

/// Filter pills: selected is navy with white text, the rest are quiet white with navy text.
struct AlongPillRow<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var badge: (Item) -> Int = { _ in 0 }
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    let selected = item == selection
                    Button { Haptics.selection(); alongWithAnimation(.smooth(duration: 0.22)) { selection = item } } label: {
                        HStack(spacing: 6) {
                            Text(title(item)).font(.system(size: 14, weight: .semibold))
                            if badge(item) > 0 {
                                Text("\(badge(item))").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(selected ? AlongColor.navy : .white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(selected ? .white : AlongColor.navy, in: Capsule())
                            }
                        }
                        .foregroundStyle(selected ? .white : AlongColor.navy)
                        .padding(.horizontal, 13).frame(minHeight: 40)
                        .background(selected ? AlongColor.navy : AlongColor.white, in: Capsule())
                        .overlay(Capsule().stroke(selected ? .clear : AlongColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Walk imagery

/// A real aerial snapshot of where a walk starts (Apple Maps imagery with 3D buildings), rendered once and cached.
/// While it loads, or if it can't, a calm navy gradient with a walking glyph stands in. Only the walk's already-public,
/// approximate start point is used.
struct WalkSnapshotView: View {
    let activity: Activity
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [AlongColor.navy, AlongColor.navy.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "figure.walk").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.35))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                        .transition(.opacity)
                }
            }
            .task(id: "\(activity.id)-\(Int(geo.size.width))") {
                guard geo.size.width > 10 else { return }
                let img = await WalkSnapshot.image(for: activity, size: geo.size)
                withAnimation(.easeOut(duration: 0.3)) { image = img }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

@MainActor
enum WalkSnapshot {
    private static let cache = NSCache<NSString, UIImage>()
    private static var inflight: [String: Task<UIImage?, Never>] = [:]

    static func image(for activity: Activity, size: CGSize) async -> UIImage? {
        let key = "\(activity.id)-\(Int(size.width))x\(Int(size.height))"
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let task = inflight[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            let options = MKMapSnapshotter.Options()
            options.camera = MKMapCamera(lookingAtCenter: activity.mapCoordinate, fromDistance: 900, pitch: 55, heading: ExploreViewModel.gridHeading)
            options.size = size
            options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
            guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
            return snapshot.image
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result { cache.setObject(result, forKey: key as NSString) }
        return result
    }
}

/// A small stat tile (Profile).
struct StatTile: View {
    let symbol: String
    let value: String
    let label: String
    var tint: Color = AlongColor.surface

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(AlongColor.navy)
            Text(value).font(.system(size: 28, weight: .bold)).foregroundStyle(AlongColor.navy).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .padding(AlongSpacing.md - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
