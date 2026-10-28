import SwiftUI

/// Monogram avatar in a muted tone. Real photos slot in here once there's a backend.
struct AlongProfileAvatar: View {
    let user: User
    var size: CGFloat = 40

    var body: some View {
        Text(user.initial)
            .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
            .foregroundStyle(AlongColor.navy)
            .frame(width: size, height: size)
            .background(AlongColor.avatarTones[user.avatarTone % AlongColor.avatarTones.count], in: Circle())
            .overlay(Circle().stroke(AlongColor.white, lineWidth: size > 60 ? 3 : 1.5))
            .accessibilityElement()
            .accessibilityLabel("\(user.firstName)'s profile picture")
    }
}
