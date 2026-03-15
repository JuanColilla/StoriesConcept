import SwiftUI

struct StoryProgressBar: View {
    let totalSegments: Int
    let activeIndex: Int
    let activeProgress: Double
    let isSeenAt: (Int) -> Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<totalSegments, id: \.self) { index in
                SegmentView(fillFraction: fillFraction(for: index))
            }
        }
        .frame(height: 3)
    }

    private func fillFraction(for index: Int) -> Double {
        if index < activeIndex {
            return 1.0
        } else if index == activeIndex {
            return activeProgress
        } else {
            return 0
        }
    }
}

// MARK: - Single Segment (no GeometryReader)

private struct SegmentView: View {
    let fillFraction: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(0.3))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}
