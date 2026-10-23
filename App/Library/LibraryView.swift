import SwiftData
import SwiftUI

/// Every story made on this device. Works signed out and offline: the script and the audio
/// are stored here.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Story.createdAt, order: .reverse) private var stories: [Story]

    var body: some View {
        NavigationStack {
            Group {
                if stories.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .inkBackground()
            .navigationTitle("Library")
        }
    }

    private var list: some View {
        List {
            ForEach(stories) { story in
                NavigationLink(value: story.id) {
                    row(story)
                }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.line)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(for: UUID.self) { id in
            if let story = stories.first(where: { $0.id == id }) {
                StoryDetailView(story: story)
            }
        }
    }

    private func row(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
            Text(subtitle(story))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ story: Story) -> String {
        var parts = [story.style, story.voice]
        if story.durationSeconds > 0 { parts.append(TimeFormat.clock(story.durationSeconds)) }
        parts.append(story.createdAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private var empty: some View {
        VStack(spacing: 18) {
            SpeakingOrb(mode: .still, size: 130)
            Text("No stories yet")
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(Theme.cream)
            Group {
                if app.isSignedIn {
                    Text("Stories you ask for appear here, and play without a connection.")
                } else {
                    Text("Sign in on the Perform tab to ask for a story. Stories you make appear here, and play without a connection.")
                }
            }
            .font(.callout)
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let story = stories[index]
            app.forget(story)
            context.delete(story)
        }
        try? context.save()
    }
}
