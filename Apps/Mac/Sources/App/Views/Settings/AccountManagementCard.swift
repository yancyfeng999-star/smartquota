import SwiftUI
import Domain

/// Settings card for managing accounts on a multi-account provider.
///
/// Shows the list of configured accounts with options to add, remove,
/// and set the active account. Only rendered for providers that conform
/// to `MultiAccountProvider`.
struct AccountManagementCard: View {
    let provider: any MultiAccountProvider
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var isExpanded = false
    @State private var showAddSheet = false
    @State private var accountToDeleteId: String?
    @State private var showDeleteConfirm = false

    private var l10n: L10n { L10n.shared }

    var body: some View {
        SettingsExpandableCard(isExpanded: $isExpanded) {
            header
        } content: {
            VStack(spacing: 8) {
                // Pending confirmation accounts
                let pending = monitor.pendingConfirmations(for: provider.id)
                if !pending.isEmpty {
                    PendingAccountBanner(
                        providerId: provider.id,
                        pendingAccounts: pending,
                        onConfirm: { accountId in
                            monitor.confirmAccount(accountId, forProvider: provider.id)
                        },
                        onIgnore: { accountId in
                            monitor.ignoreAccount(accountId, forProvider: provider.id)
                        }
                    )
                }

                // Connected / disconnected accounts
                ForEach(provider.accounts, id: \.id) { account in
                    accountRow(account)
                }

                addAccountButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet(provider: provider, monitor: monitor)
        }
        .alert(
            l10n.t("account.delete_title"),
            isPresented: $showDeleteConfirm
        ) {
            Button(l10n.t("account.delete"), role: .destructive) {
                if let accountId = accountToDeleteId {
                    monitor.deleteAccount(accountId, forProvider: provider.id)
                    accountToDeleteId = nil
                }
            }
            Button(l10n.t("common.cancel"), role: .cancel) {
                accountToDeleteId = nil
            }
        } message: {
            Text(l10n.t("account.delete_message"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.tf("account.count_fmt", "\(provider.accounts.count)"))
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(subtitleText)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            // Aggregate status badge (chevron is added by SettingsExpandableCard)
            let statusColor = theme.statusColor(for: provider.aggregateStatus)
            Text(provider.aggregateStatus.badgeText)
                .badge(statusColor)
        }
    }

    private var subtitleText: String {
        let connected = provider.accounts.filter { account in
            connectionState(for: account) == .connected
        }.count
        let pending = monitor.pendingConfirmations(for: provider.id).count
        var parts: [String] = []
        if connected > 0 {
            parts.append("\(connected) \(l10n.t("account.connected"))")
        }
        if pending > 0 {
            parts.append("\(pending) \(l10n.t("account.pending"))")
        }
        return parts.isEmpty ? l10n.t("account.no_accounts") : parts.joined(separator: " · ")
    }

    // MARK: - Account Row

    private func accountRow(_ account: ProviderAccount) -> some View {
        let state = connectionState(for: account)
        let isActive = account.accountId == provider.activeAccount.accountId

        return HStack(spacing: 10) {
            // Avatar with state indicator
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        isActive
                            ? theme.accentPrimary
                            : theme.glassBackground
                    )
                    .frame(width: 24, height: 24)

                Text(account.initialLetter)
                    .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(
                        isActive
                            ? .white
                            : theme.textSecondary
                    )

                // State indicator dot
                Circle()
                    .fill(stateDotColor(for: state))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(theme.cardGradient, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)
            }

            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let email = account.email {
                        Text(email)
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }

                    // State label
                    Text(stateLabel(for: state))
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(stateDotColor(for: state))
                }
            }

            Spacer()

            // Status from snapshot
            if let snapshot = provider.accountSnapshots[account.accountId] {
                let status = snapshot.overallStatus
                Circle()
                    .fill(theme.statusColor(for: status))
                    .frame(width: 8, height: 8)
            }

            // Active indicator or switch button
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.statusHealthy)
                    .accessibilityLabel(l10n.t("account.active"))
            } else if state == .connected {
                Button {
                    provider.switchAccount(to: account.accountId)
                } label: {
                    Text(l10n.t("account.switch"))
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.accentPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .stroke(theme.accentPrimary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(l10n.t("account.switch")) \(account.displayName)")
            }

            // Delete button (not for active account)
            if !isActive {
                Button {
                    accountToDeleteId = account.accountId
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(l10n.t("account.delete")) \(account.displayName)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Account

    private var addAccountButton: some View {
        Button {
            showAddSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text(l10n.t("account.add"))
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            }
            .foregroundStyle(theme.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accentPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("account.add"))
    }

    // MARK: - Helpers

    private func connectionState(for account: ProviderAccount) -> AccountConnectionState {
        if let status = account.membershipStatus {
            return status.asConnectionState
        }
        return .connected
    }

    private func stateDotColor(for state: AccountConnectionState) -> Color {
        switch state {
        case .connected:
            return theme.statusHealthy
        case .disconnected:
            return theme.statusCritical
        case .pendingConfirmation:
            return theme.statusWarning
        }
    }

    private func stateLabel(for state: AccountConnectionState) -> String {
        switch state {
        case .connected:
            return l10n.t("account.connected")
        case .disconnected:
            return l10n.t("account.disconnected")
        case .pendingConfirmation:
            return l10n.t("account.pending")
        }
    }
}
