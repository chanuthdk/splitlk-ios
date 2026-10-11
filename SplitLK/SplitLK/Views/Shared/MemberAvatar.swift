import SwiftUI

struct MemberAvatar: View {
    let member: CDMember
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Color(hex: member.colorHex ?? "4F46E5"))
            .frame(width: size, height: size)
            .overlay(
                Text(member.initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(member.displayName)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
