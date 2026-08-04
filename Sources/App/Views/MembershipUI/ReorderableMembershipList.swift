import SwiftUI
import AppKit
import Domain

/// Normal: clean cards only.
/// Long-press any card → enter reorder mode (↑↓ controls).
/// Tap「完成排序」to exit.
struct ReorderableMembershipList: View {
    let providers: [any AIProvider]
    let selectedId: String
    let onSelect: (String) -> Void
    let onReorder: ([String]) -> Void

    @State private var orderIds: [String] = []
    @State private var isReorderMode = false

    var body: some View {
        VStack(spacing: 8) {
            if isReorderMode {
                reorderBanner
            }

            VStack(spacing: 9) {
                ForEach(Array(orderIds.enumerated()), id: \.element) { index, id in
                    if let provider = provider(for: id) {
                        HStack(alignment: .center, spacing: 6) {
                            ProviderSummaryCardView(
                                provider: provider,
                                isSelected: provider.id == selectedId,
                                onSelect: {
                                    if isReorderMode { return }
                                    onSelect(id)
                                }
                            )
                            .frame(maxWidth: .infinity)
                            // Long-press card → enter sort mode
                            .onLongPressGesture(minimumDuration: 0.4) {
                                enterReorderMode()
                            }

                            if isReorderMode {
                                reorderControls(id: id, index: index)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .animation(AppMotion.selection, value: isReorderMode)
            .animation(AppMotion.selection, value: orderIds)
        }
        .onAppear { syncOrder() }
        .onChange(of: providers.map(\.id)) { _, ids in
            var next = orderIds.filter { ids.contains($0) }
            for id in ids where !next.contains(id) { next.append(id) }
            orderIds = next.isEmpty ? ids : next
        }
    }

    private var reorderBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MembershipPalette.accentPrimary)
            Text(L10n.shared.t("menu.sort_mode"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                AppMotion.withSelection {
                    isReorderMode = false
                }
            } label: {
                Text(L10n.shared.t("common.done"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MembershipPalette.accentPrimary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MembershipPalette.accentPrimary.opacity(0.08))
        )
    }

    private func reorderControls(id: String, index: Int) -> some View {
        VStack(spacing: 2) {
            Button { moveUp(id: id) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .foregroundStyle(index == 0 ? Color.secondary.opacity(0.3) : Color.primary)

            Button { moveDown(id: id) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index >= orderIds.count - 1)
            .foregroundStyle(index >= orderIds.count - 1 ? Color.secondary.opacity(0.3) : Color.primary)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func enterReorderMode() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        AppMotion.withSelection {
            isReorderMode = true
        }
    }

    private func moveUp(id: String) {
        guard let i = orderIds.firstIndex(of: id), i > 0 else { return }
        AppMotion.withSelection {
            orderIds.swapAt(i, i - 1)
            onReorder(orderIds)
        }
    }

    private func moveDown(id: String) {
        guard let i = orderIds.firstIndex(of: id), i < orderIds.count - 1 else { return }
        AppMotion.withSelection {
            orderIds.swapAt(i, i + 1)
            onReorder(orderIds)
        }
    }

    private func syncOrder() {
        orderIds = providers.map(\.id)
    }

    private func provider(for id: String) -> (any AIProvider)? {
        providers.first { $0.id == id }
    }
}
