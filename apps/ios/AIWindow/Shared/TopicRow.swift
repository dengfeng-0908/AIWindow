import SwiftUI

struct TopicRow: View {
    let topic: TopicRecord
    var showsVisitCount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.displayTitle)
                .font(.body.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(topic.lastVisitedAt.formatted(.relative(presentation: .named)))
                if showsVisitCount {
                    Text("·")
                    Text("访问 \(topic.visitCount) 次")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if topic.needsTitleRefresh {
                Label("打开帖子后自动恢复标题", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !topic.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(topic.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
