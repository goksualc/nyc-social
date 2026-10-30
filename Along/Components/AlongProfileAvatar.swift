import SwiftUI

/// Profile picture: the person's photo when they have one (and we may see it), otherwise a muted monogram.
struct AlongProfileAvatar: View {
    let user: User
    var size: CGFloat = 40

    @Environment(\.avatarLoader) private var loader
    @State private var photoURL: URL?

    var body: some View {
        ZStack {
            monogram
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill().transition(.opacity) }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(AlongColor.white, lineWidth: size > 60 ? 3 : 1.5))
        .accessibilityElement()
        .accessibilityLabel("\(user.firstName)'s profile picture")
        .task(id: user.avatarPath) {
            guard let path = user.avatarPath, let loader else { photoURL = nil; return }
            photoURL = await loader.url(for: path)
        }
    }

    private var monogram: some View {
        Text(user.initial)
            .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
            .foregroundStyle(AlongColor.navy)
            .frame(width: size, height: size)
            .background(AlongColor.avatarTones[user.avatarTone % AlongColor.avatarTones.count], in: Circle())
    }
}
