import SwiftUI

struct AIHotItemDetailView: View {
    let item: AIHotItem

    var body: some View {
        AIHotStoryDetailView(
            title: item.title,
            summary: item.cleanSummary,
            sourceName: item.source.name,
            categoryName: item.categoryName,
            date: item.displayDate,
            links: item.links,
            attribution: item.attribution
        )
    }
}

struct AIHotDailyItemDetailView: View {
    let item: AIHotDailyItem

    var body: some View {
        AIHotStoryDetailView(
            title: item.title,
            summary: item.summary,
            sourceName: item.source.name,
            categoryName: nil,
            date: nil,
            links: item.links,
            attribution: item.attribution
        )
    }
}

struct AIHotDailyFlashDetailView: View {
    let flash: AIHotDailyFlash

    var body: some View {
        AIHotStoryDetailView(
            title: flash.title,
            summary: nil,
            sourceName: flash.source.name,
            categoryName: "快讯",
            date: flash.publishedAt,
            links: flash.links,
            attribution: flash.attribution
        )
    }
}

struct AIHotTopicDetailView: View {
    let topic: AIHotTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(topic.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 10) {
                    Label(topic.source.name, systemImage: "newspaper")
                    Label("\(topic.sourceCount) 个来源", systemImage: "square.stack.3d.up")
                    if topic.signalCount > 0 {
                        Label("\(topic.signalCount) 条热点信号", systemImage: "waveform")
                    }
                    Label(
                        topic.latestAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !topic.sourceNames.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("涉及来源")
                            .font(.headline)
                        Text(topic.sourceNames.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                AIHotLinkActions(links: topic.links)

                AIHotAttributionLabel(
                    attribution: nil,
                    fallbackURL: topic.links.aihot ?? AIHotClient.productionBaseURL
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("热点详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: topic.links.original) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享原文")
            }
        }
    }
}

private struct AIHotStoryDetailView: View {
    let title: String
    let summary: String?
    let sourceName: String
    let categoryName: String?
    let date: Date?
    let links: AIHotContentLinks
    let attribution: AIHotAttribution?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 10) {
                    Label(sourceName, systemImage: "newspaper")
                    if let categoryName {
                        Label(categoryName, systemImage: "tag")
                    }
                    if let date {
                        Label(
                            date.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "clock"
                        )
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI HOT 摘要")
                            .font(.headline)
                        Text(summary)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                AIHotLinkActions(links: links)

                AIHotAttributionLabel(
                    attribution: attribution,
                    fallbackURL: links.aihot ?? AIHotClient.productionBaseURL
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("资讯详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: links.original) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享原文")
            }
        }
    }
}

private struct AIHotLinkActions: View {
    let links: AIHotContentLinks

    var body: some View {
        VStack(spacing: 10) {
            Link(destination: links.original) {
                Label("阅读原文", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let aihotURL = links.aihot {
                Link(destination: aihotURL) {
                    Label("在 AI HOT 查看", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}
