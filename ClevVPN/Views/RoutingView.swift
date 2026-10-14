import SwiftUI
import ClevVPNKit

/// Режим трафика и правила по доменам/IP — 1:1 с `MacRulesView`.
struct RulesTabView: View {
    @EnvironmentObject private var state: AppState
    @State private var newValue = ""
    @State private var newMatcher: RoutingRule.Matcher = .domainSuffix
    @State private var newTarget: RoutingRule.Target = .direct

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Traffic mode")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    modeRadio(.global, title: "All traffic via VPN")
                    modeRadio(.custom, title: "Custom rules")
                }
                .onChangeCompat(of: state.routingMode) { _ in
                    Task { await state.reconnectIfConnected() }
                }

                Text(modeHint)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                Divider().overlay(Theme.stroke)

                Text("Security")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kill Switch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Blocks all internet if the VPN drops — your real IP never leaks.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $state.killSwitchEnabled)
                        .labelsHidden()
                        .tint(Theme.yellow)
                }

                Divider().overlay(Theme.stroke)

                Text("My rules")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                // Как на Mac: поле + тип + действие + «+»; на узком экране
                // пикеры переносятся на вторую строку.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ruleTextField
                        matcherMenu.frame(width: 110)
                        targetMenu.frame(width: 120)
                        addButton
                    }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ruleTextField
                            addButton
                        }
                        HStack(spacing: 8) {
                            matcherMenu
                            targetMenu
                        }
                    }
                }

                ForEach(state.customRules) { rule in
                    HStack(spacing: 10) {
                        Image(systemName: rule.matcher == .domainSuffix ? "network" : "number")
                            .foregroundColor(Theme.textSecondary)
                        Text(rule.value)
                            .font(.subheadline)
                            .foregroundColor(Theme.textPrimary)
                        Text(rule.target == .direct ? "Bypass VPN" : "Via VPN")
                            .font(.caption)
                            .foregroundColor(rule.target == .direct ? Theme.orange : Theme.green)
                        Spacer()
                        Toggle("", isOn: binding(for: rule))
                            .labelsHidden()
                            .tint(Theme.yellow)
                        Button {
                            state.customRules.removeAll { $0.id == rule.id }
                            Task { await state.reconnectIfConnected() }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Theme.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .card()
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var ruleTextField: some View {
        TextField(newMatcher == .domainSuffix ? "example.com" : "192.168.1.0/24", text: $newValue)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.done)
            .onSubmit(addRule)
    }

    private var matcherMenu: some View {
        Menu {
            Picker(selection: $newMatcher) {
                Text("Domain").tag(RoutingRule.Matcher.domainSuffix)
                Text("IP / CIDR").tag(RoutingRule.Matcher.ipCIDR)
            } label: { EmptyView() }
        } label: {
            pickerLabel(newMatcher == .domainSuffix ? "Domain" : "IP / CIDR")
        }
    }

    private var targetMenu: some View {
        Menu {
            Picker(selection: $newTarget) {
                Text("Bypass VPN").tag(RoutingRule.Target.direct)
                Text("Via VPN").tag(RoutingRule.Target.proxy)
            } label: { EmptyView() }
        } label: {
            pickerLabel(newTarget == .direct ? "Bypass VPN" : "Via VPN")
        }
    }

    private var addButton: some View {
        Button {
            addRule()
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(Theme.yellow)
        }
        .buttonStyle(.plain)
    }

    /// Радиокнопка режима — визуально как `.radioGroup` на macOS.
    private func modeRadio(_ mode: RoutingMode, title: LocalizedStringKey) -> some View {
        Button {
            state.routingMode = mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.routingMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(state.routingMode == mode ? Theme.yellow : Theme.stroke)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickerLabel(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Подсказка под выбранным режимом — тот же текст, что на macOS/Windows/Android.
    private var modeHint: LocalizedStringKey {
        switch state.routingMode {
        case .global: return "All traffic goes through VPN"
        case .custom: return "Only your domain/IP rules"
        }
    }

    private func addRule() {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.customRules.append(RoutingRule(value: trimmed, matcher: newMatcher, target: newTarget))
        newValue = ""
        Task { await state.reconnectIfConnected() }
    }

    private func binding(for rule: RoutingRule) -> Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                if let index = state.customRules.firstIndex(where: { $0.id == rule.id }) {
                    state.customRules[index].isEnabled = newValue
                    Task { await state.reconnectIfConnected() }
                }
            }
        )
    }
}
