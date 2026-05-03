import SwiftUI

struct ActivityView: View {
    @ObservedObject var store: BarelyRealStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(store.logLines.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.logLines.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No events yet")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Start a session and you'll see traffic here.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            ForEach(Array(store.logLines.enumerated()), id: \.offset) { index, line in
                                EventRow(line: line)
                                    .background(index.isMultiple(of: 2)
                                                ? Color.clear
                                                : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .id(index)
                            }
                        }
                    }
                }
                .onChange(of: store.logLines.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
