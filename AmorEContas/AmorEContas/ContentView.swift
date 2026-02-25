//
//  ContentView.swift
//  AmorEContas
//
//  Created by Kett Lima on 16/02/26.
//

import SwiftUI
import StoreKit
import UIKit

private enum ActiveSheet: Identifiable, Equatable {
    case settings
    case addExpense

    var id: Int {
        switch self {
        case .settings: return 1
        case .addExpense: return 2
        }
    }
}

struct ContentView: View {
    @StateObject private var store = AmorEContasStore()
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage("hasSeenAboutOnFirstLaunch") private var hasSeenAboutOnFirstLaunch = false
    @AppStorage("appLanguageCode") private var appLanguageCode = L10n.systemLanguageCode
    @AppStorage("showDetailedSettlement") private var showDetailedSettlement = false

    @State private var activeSheet: ActiveSheet?
    @State private var selectedPersonId: UUID?
    @State private var newExpenseName = ""
    @State private var newExpenseAmountText = ""
    @State private var showUpgradeSheet = false
    @State private var showAboutOnFirstLaunch = false
    @State private var upgradeReason = ""
    @State private var showAddExpenseSuccessAlert = false
    @State private var addExpenseSuccessMessage = ""
    @State private var showAddExpenseValidationAlert = false
    @State private var addExpenseFocusToken = UUID()
    @State private var showCopySettlementSuccessAlert = false

    private let freePeopleLimit = 2
    private let freeExpensesPerPersonLimit = 1
    private let supportedLanguageCodes = ["en", "pt-BR", "es", "fr", "de", "it", "nl", "tr", "ru", "ja", "ko", "zh-Hans"]

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("summary.section.title")) {
                    ForEach(store.state.people) { person in
                        row(L10n.format("summary.paid", person.name), store.format(store.totalPaid(for: person.id)))
                    }

                    row(L10n.text("summary.total"), store.format(store.totalAll))
                    Divider()

                    ForEach(store.state.people) { person in
                        row(L10n.format("summary.fairShare", person.name), store.format(store.share(for: person.id)))
                    }
                }

                Section(L10n.text("division.section.title")) {
                    ForEach(store.state.people) { person in
                        row(L10n.format("division.share", person.name), "\(Int(store.splitPct(for: person.id).rounded()))%")
                    }
                }

                Section(L10n.text("settlement.section.title")) {
                    Text(store.settlementMessage)

                    if showDetailedSettlement {
                        Text(store.settlementDetailedMessage)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if shouldUseCopySettlementAction {
                        Button {
                            UIPasteboard.general.string = settlementMessageToShare
                            showCopySettlementSuccessAlert = true
                        } label: {
                            Label(L10n.text("settlement.copy"), systemImage: "doc.on.doc")
                        }
                    } else {
                        ShareLink(item: settlementMessageToShare) {
                            Label(L10n.text("settlement.share"), systemImage: "square.and.arrow.up")
                        }
                    }
                }

                ForEach(store.state.people) { person in
                    expenseListSection(
                        title: L10n.format("expenses.section.title", person.name),
                        personId: person.id,
                        payments: person.payments
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedPersonId = selectedPersonId ?? store.state.people.first?.id
                        addExpenseFocusToken = UUID()
                        activeSheet = .addExpense
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    settingsSheet
                case .addExpense:
                    addExpenseSheet
                }
            }
            .onAppear {
                selectedPersonId = selectedPersonId ?? store.state.people.first?.id
                if !hasSeenAboutOnFirstLaunch {
                    showAboutOnFirstLaunch = true
                }
            }
            .onChange(of: store.state.people.map(\.id)) { _, _ in
                syncSelectedPerson()
            }
            .alert(L10n.text("alert.copied.title"), isPresented: $showCopySettlementSuccessAlert) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                Text(L10n.text("alert.settlementCopied.message"))
            }
            .sheet(
                isPresented: $showAboutOnFirstLaunch,
                onDismiss: {
                    hasSeenAboutOnFirstLaunch = true
                }
            ) {
                NavigationStack {
                    AboutAppSlidesView(
                        showsContinueButton: true,
                        onContinue: {
                            hasSeenAboutOnFirstLaunch = true
                            showAboutOnFirstLaunch = false
                        }
                    )
                }
            }
            .tint(.pink)
        }
    }

    private func expenseListSection(
        title: String,
        personId: UUID,
        payments: [Payment]
    ) -> some View {
        Section(title) {
            if payments.isEmpty {
                Text(L10n.text("expenses.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(payment.description)
                            Text(store.format(payment.amount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .onDelete { offsets in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        store.removePayments(for: personId, at: offsets)
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: payments.count)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section(L10n.text("settings.people.section")) {
                    ForEach($store.state.people) { $person in
                        TextField(L10n.text("settings.name.placeholder"), text: $person.name)
                    }
                    .onDelete { offsets in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            store.removePeople(at: offsets)
                            syncSelectedPerson()
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            if purchaseManager.isFullUnlocked || store.state.people.count < freePeopleLimit {
                                store.addPerson()
                                syncSelectedPerson()
                            } else {
                                upgradeReason = L10n.text("upgrade.people.limit.reason")
                                showUpgradeSheet = true
                            }
                        }
                    } label: {
                        Label {
                            Text(L10n.text("settings.addPerson"))
                        } icon: {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(.pink)
                        }
                    }
                }

                Section(L10n.text("settings.section.title")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("settings.currency.label"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(L10n.text("settings.currency.placeholder"), text: $store.state.settings.currencySymbol)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }
                    .padding(.vertical, 4)

                    Picker(L10n.text("settings.splitMode.label"), selection: $store.state.settings.splitMode) {
                        Text(L10n.text("settings.splitMode.automatic")).tag(SplitMode.automaticScale)
                        Text(L10n.text("settings.splitMode.equal")).tag(SplitMode.equal50)
                    }

                    Toggle(L10n.text("settings.settlementDetailed.toggle"), isOn: $showDetailedSettlement)

                    NavigationLink {
                        languageSelectionView
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text("settings.language.label"))
                            Text(selectedLanguageName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if store.state.settings.splitMode == .automaticScale {
                    Section(L10n.text("settings.scale.section")) {
                        ForEach($store.state.people) { $person in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(person.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                TextField("1", text: textBinding(for: $person.scale))
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(L10n.text("settings.about.section")) {
                    NavigationLink {
                        AboutAppSlidesView()
                    } label: {
                        Label {
                            Text(L10n.text("settings.about.link"))
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.pink)
                        }
                    }
                }

                #if DEBUG
                Section("Debug") {
                    Button("Add sample data") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            store.loadSampleData()
                            selectedPersonId = store.state.people.first?.id
                        }
                    }
                }
                #endif

                Section {
                    Color.clear
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in dismissKeyboard() }
            )
            .navigationTitle(L10n.text("settings.nav.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close")) {
                        store.save()
                        syncSelectedPerson()
                        activeSheet = nil
                    }
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                UpgradeSheet(reason: upgradeReason)
                    .environmentObject(purchaseManager)
            }
        }
    }

    private var addExpenseSheet: some View {
        NavigationStack {
            Form {
                if store.state.people.isEmpty {
                    Section {
                        Text(L10n.text("addExpense.noPeople"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    addExpenseSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in dismissKeyboard() }
            )
            .alert(L10n.text("alert.expenseAdded.title"), isPresented: $showAddExpenseSuccessAlert) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                Text(addExpenseSuccessMessage)
            }
            .alert(L10n.text("alert.invalidAmount.title"), isPresented: $showAddExpenseValidationAlert) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                Text(L10n.text("alert.invalidAmount.message"))
            }
            .sheet(isPresented: $showUpgradeSheet) {
                UpgradeSheet(reason: upgradeReason)
                    .environmentObject(purchaseManager)
            }
        }
    }

    private var addExpenseSection: some View {
        Section(L10n.text("addExpense.section.title")) {
            let fallbackPersonId = store.state.people.first?.id ?? UUID()

            Picker(
                L10n.text("addExpense.paidBy"),
                selection: Binding(
                    get: { selectedPersonId ?? fallbackPersonId },
                    set: { selectedPersonId = $0 }
                )
            ) {
                ForEach(store.state.people) { person in
                    Text(person.name).tag(person.id)
                }
            }
            .paidByPickerStyle(for: store.state.people.count)

            AutoFocusAmountField(
                text: $newExpenseAmountText,
                focusToken: addExpenseFocusToken
            )
            TextField(L10n.text("addExpense.name.placeholder"), text: $newExpenseName)

            if let amount = parseNumber(newExpenseAmountText), amount > 0 {
                let targetId = selectedPersonId ?? fallbackPersonId

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("addExpense.preview.title"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(store.state.people) { person in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.name)
                                    .font(.subheadline)

                                HStack {
                                    Text(L10n.text("addExpense.preview.share"))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(store.format(expenseShareOfAddedAmount(for: person.id, addedAmount: amount)))
                                }
                                .font(.caption)
                                HStack {
                                    Text(L10n.text("addExpense.preview.totalAfter"))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(store.format(store.totalPaid(for: person.id) + (person.id == targetId ? amount : 0)))
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                let targetId = selectedPersonId ?? fallbackPersonId

                guard let amount = parseNumber(newExpenseAmountText), amount > 0 else {
                    showAddExpenseValidationAlert = true
                    return
                }

                if !purchaseManager.isFullUnlocked,
                   store.paymentCount(for: targetId) >= freeExpensesPerPersonLimit {
                    upgradeReason = L10n.text("upgrade.expenses.limit.reason")
                    showUpgradeSheet = true
                    return
                }

                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    store.addPayment(
                        for: targetId,
                        description: newExpenseName.trimmingCharacters(in: .whitespacesAndNewlines),
                        amount: amount
                    )
                }

                let personName = store.state.people.first(where: { $0.id == targetId })?.name ?? L10n.text("addExpense.selectedPersonFallback")
                let expenseLabel = newExpenseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L10n.text("addExpense.expenseFallback")
                    : newExpenseName.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedPersonTotal = store.totalPaid(for: targetId)
                addExpenseSuccessMessage = L10n.format(
                    "addExpense.success.message",
                    expenseLabel,
                    personName,
                    store.format(amount),
                    store.format(updatedPersonTotal)
                )
                showAddExpenseSuccessAlert = true

                newExpenseName = ""
                newExpenseAmountText = ""
                addExpenseFocusToken = UUID()
            } label: {
                Text(L10n.text("addExpense.button"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .bold()
        }
    }

    private var languageSelectionView: some View {
        List {
            Section {
                languageRow(code: L10n.systemLanguageCode)
                ForEach(supportedLanguageCodes, id: \.self) { code in
                    languageRow(code: code)
                }
            } footer: {
                Text(L10n.text("settings.language.helper"))
            }
        }
        .navigationTitle(L10n.text("settings.language.nav.title"))
    }

    private func languageRow(code: String) -> some View {
        Button {
            appLanguageCode = code
        } label: {
            HStack {
                Text(languageName(for: code))
                Spacer()
                if appLanguageCode == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.pink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedLanguageName: String {
        languageName(for: appLanguageCode)
    }

    private func languageName(for code: String) -> String {
        switch code {
        case L10n.systemLanguageCode:
            return L10n.text("settings.language.system")
        case "en":
            return L10n.text("settings.language.en")
        case "pt-BR":
            return L10n.text("settings.language.ptBR")
        case "es":
            return L10n.text("settings.language.es")
        case "fr":
            return L10n.text("settings.language.fr")
        case "de":
            return L10n.text("settings.language.de")
        case "it":
            return L10n.text("settings.language.it")
        case "nl":
            return L10n.text("settings.language.nl")
        case "tr":
            return L10n.text("settings.language.tr")
        case "ru":
            return L10n.text("settings.language.ru")
        case "ja":
            return L10n.text("settings.language.ja")
        case "ko":
            return L10n.text("settings.language.ko")
        case "zh-Hans":
            return L10n.text("settings.language.zhHans")
        default:
            return L10n.text("settings.language.system")
        }
    }

    private func parseNumber(_ text: String) -> Double? {
        let sanitized = text.replacingOccurrences(of: ",", with: ".")
        return Double(sanitized)
    }

    private func expenseShareOfAddedAmount(for personId: UUID, addedAmount: Double) -> Double {
        guard !store.state.people.isEmpty else { return 0 }

        if store.state.settings.splitMode == .equal50 {
            return addedAmount / Double(store.state.people.count)
        }

        let totalScale = store.positiveScaleTotal
        if totalScale <= 0 {
            return addedAmount / Double(store.state.people.count)
        }

        guard let person = store.state.people.first(where: { $0.id == personId }) else { return 0 }
        return addedAmount * (max(0, person.scale) / totalScale)
    }

    private func textBinding(for value: Binding<Double>) -> Binding<String> {
        Binding(
            get: { plainNumber(value.wrappedValue) },
            set: { newValue in
                if newValue.isEmpty {
                    value.wrappedValue = 0
                    return
                }
                if let parsed = parseNumber(newValue) {
                    value.wrappedValue = parsed
                }
            }
        )
    }

    private func syncSelectedPerson() {
        guard !store.state.people.isEmpty else {
            selectedPersonId = nil
            return
        }

        if let selectedPersonId,
           store.state.people.contains(where: { $0.id == selectedPersonId }) {
            return
        }

        selectedPersonId = store.state.people.first?.id
    }

    private func plainNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }

    private var settlementMessageToShare: String {
        let baseMessage: String
        if showDetailedSettlement {
            baseMessage = "\(store.settlementMessage)\n\n\(store.settlementDetailedMessage)"
        } else {
            baseMessage = store.settlementMessage
        }
        return "\(baseMessage)\(L10n.text("settlement.signature"))"
    }

    private var shouldUseCopySettlementAction: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

}

private struct AutoFocusAmountField: UIViewRepresentable {
    @Binding var text: String
    let focusToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = L10n.text("addExpense.amount.placeholder")
        textField.keyboardType = .decimalPad
        textField.textAlignment = .natural
        textField.clearButtonMode = .whileEditing
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if context.coordinator.lastFocusedToken != focusToken {
            context.coordinator.lastFocusedToken = focusToken
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var lastFocusedToken: UUID?

        init(text: Binding<String>) {
            _text = text
        }

        @objc
        func textDidChange(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

private extension View {
    @ViewBuilder
    func paidByPickerStyle(for peopleCount: Int) -> some View {
        if peopleCount == 2 {
            self.pickerStyle(.segmented)
        } else {
            self.pickerStyle(.inline)
        }
    }
}

private struct UpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager

    let reason: String

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("upgrade.full.section")) {
                    Text(reason)
                        .font(.subheadline)

                    Text(L10n.text("upgrade.unlimited.description"))
                        .foregroundStyle(.secondary)

                    if purchaseManager.isFullUnlocked {
                        Label(L10n.text("upgrade.active"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await purchaseManager.buyFullAccess() }
                        } label: {
                            HStack {
                                Text(L10n.text("upgrade.buy"))
                                Spacer()
                                if let product = purchaseManager.product {
                                    Text(product.displayPrice)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(purchaseManager.isPurchasing)

                        Button(L10n.text("upgrade.restore")) {
                            Task { await purchaseManager.restorePurchases() }
                        }
                        .disabled(purchaseManager.isPurchasing)
                    }

                    if purchaseManager.isLoadingProduct {
                        ProgressView(L10n.text("upgrade.loadingProduct"))
                    }

                    if let purchaseMessage = purchaseManager.purchaseMessage {
                        Text(purchaseMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.text("upgrade.nav.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close")) { dismiss() }
                }
            }
            .task {
                if purchaseManager.product == nil {
                    await purchaseManager.refreshProducts()
                }
            }
        }
    }
}

private struct AboutAppSlidesView: View {
    var showsContinueButton: Bool = false
    var onContinue: (() -> Void)? = nil

    var body: some View {
        TabView {
            aboutSlide(
                title: L10n.text("about.what.title"),
                systemImage: "heart.text.square",
                text: L10n.text("about.what.text")
            )

            aboutSlide(
                title: L10n.text("about.why.title"),
                systemImage: "sparkles",
                text: L10n.text("about.why.text")
            )

            aboutSlide(
                title: L10n.text("about.when5050.title"),
                systemImage: "equal.circle",
                text: L10n.text("about.when5050.text")
            )

            aboutSlide(
                title: L10n.text("about.automatic.title"),
                systemImage: "chart.bar.doc.horizontal",
                text: L10n.text("about.automatic.text")
            )

            aboutSlide(
                title: L10n.text("about.suggestions.title"),
                systemImage: "lightbulb",
                text: L10n.text("about.suggestions.text")
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .navigationTitle(L10n.text("about.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsContinueButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("about.continue")) {
                        onContinue?()
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func aboutSlide(title: String, systemImage: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.pink)

            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
