import SwiftUI

struct StoryRowView: View {
    let user: User
    let unseenCount: Int
    let allSeen: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with ring (green = unseen, clear = all seen)
            AsyncImage(url: user.avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(allSeen ? Color.gray.opacity(0.3) : Color.green, lineWidth: 2.5)
                    .frame(width: 62, height: 62)
            )

            // Username
            Text(user.displayName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(allSeen ? .secondary : .primary)

            Spacer()

            // Right indicator: badge count or "Seen"
            if allSeen {
                Text("Seen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(unseenCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.green)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }
}
