import SwiftUI

struct StoryProgressBar: View {
    let totalSegments: Int
    let activeIndex: Int
    let activeProgress: Double
    let isSeenAt: (Int) -> Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<totalSegments, id: \.self) { index in
                GeometryReader { geo in
                    let width = geo.size.width

                    ZStack(alignment: .leading) {
                        // Background — brighter if previously seen, dimmer if unseen
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(backgroundOpacity(for: index)))

                        // Fill
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: fillWidth(for: index, totalWidth: width))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func fillWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < activeIndex {
            return totalWidth // Past segments: fully filled
        } else if index == activeIndex {
            return totalWidth * activeProgress // Active: progressive fill
        } else {
            return 0 // Future segments: always empty, regardless of seen state
        }
    }

    private func backgroundOpacity(for index: Int) -> Double {
        0.3 // Uniform background for all segments
    }
}
