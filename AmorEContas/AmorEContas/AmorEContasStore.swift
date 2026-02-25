import Foundation
import Combine

enum SplitMode: String, Codable, CaseIterable, Identifiable {
    case automaticScale
    case equal50

    var id: String { rawValue }
}

struct Payment: Identifiable, Codable {
    var id = UUID()
    var description: String
    var amount: Double
}

struct PersonData: Identifiable, Codable {
    var id = UUID()
    var name: String
    var income: Double
    var scale: Double
    var payments: [Payment]

    init(id: UUID = UUID(), name: String, income: Double, scale: Double = 1, payments: [Payment] = []) {
        self.id = id
        self.name = name
        self.income = income
        self.scale = scale
        self.payments = payments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case income
        case scale
        case payments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? L10n.text("store.default.person")
        income = try container.decodeIfPresent(Double.self, forKey: .income) ?? 0
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        payments = try container.decodeIfPresent([Payment].self, forKey: .payments) ?? []
    }
}

struct AppSettings: Codable {
    var currencySymbol: String
    var splitMode: SplitMode

    init(currencySymbol: String, splitMode: SplitMode) {
        self.currencySymbol = currencySymbol
        self.splitMode = splitMode
    }

    private enum CodingKeys: String, CodingKey {
        case currencySymbol
        case splitMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencySymbol = try container.decodeIfPresent(String.self, forKey: .currencySymbol) ?? "$"
        splitMode = try container.decodeIfPresent(SplitMode.self, forKey: .splitMode) ?? .automaticScale
    }
}

struct AmorEContasState: Codable {
    var people: [PersonData]
    var settings: AppSettings

    static let `default` = AmorEContasState(
        people: [
            PersonData(name: L10n.text("store.default.personA"), income: 0, scale: 1),
            PersonData(name: L10n.text("store.default.personB"), income: 0, scale: 1)
        ],
        settings: AppSettings(currencySymbol: "$", splitMode: .automaticScale)
    )

    private enum CodingKeys: String, CodingKey {
        case people
        case settings
        case personA
        case personB
    }

    init(people: [PersonData], settings: AppSettings) {
        self.people = people
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedPeople = try container.decodeIfPresent([PersonData].self, forKey: .people), !decodedPeople.isEmpty {
            people = decodedPeople
            settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings(currencySymbol: "$", splitMode: .automaticScale)
            return
        }

        let personA = try container.decodeIfPresent(PersonData.self, forKey: .personA)
        let personB = try container.decodeIfPresent(PersonData.self, forKey: .personB)
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings(currencySymbol: "$", splitMode: .automaticScale)

        var migratedPeople: [PersonData] = []
        if let first = personA {
            migratedPeople.append(first)
        }
        if let second = personB {
            migratedPeople.append(second)
        }

        people = migratedPeople.isEmpty ? AmorEContasState.default.people : migratedPeople
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(people, forKey: .people)
        try container.encode(settings, forKey: .settings)
    }
}

@MainActor
final class AmorEContasStore: ObservableObject {
    @Published var state: AmorEContasState

    init() {
        self.state = AmorEContasState.default
        load()
    }

    var totalAll: Double {
        state.people.flatMap(\.payments).reduce(0) { $0 + $1.amount }
    }

    var positiveScaleTotal: Double {
        state.people.reduce(0) { $0 + max(0, $1.scale) }
    }

    var settlementMessage: String {
        let balances = personBalances()
        let epsilon = 0.01

        if balances.allSatisfy({ abs($0.balance) <= epsilon }) {
            return L10n.text("store.settlement.balanced")
        }

        if balances.count == 2 {
            let payer = balances.first(where: { $0.balance < -epsilon })
            let receiver = balances.first(where: { $0.balance > epsilon })

            if let payer, let receiver {
                return L10n.format("store.settlement.transfer", payer.person.name, format(abs(payer.balance)), receiver.person.name)
            }
        }

        let debtors = balances.filter { $0.balance < -epsilon }
        let creditors = balances.filter { $0.balance > epsilon }

        let payerText = debtors
            .map { L10n.format("store.settlement.pays", $0.person.name, format(abs($0.balance))) }
            .joined(separator: "\n")

        let receiverText = creditors
            .map { L10n.format("store.settlement.receives", $0.person.name, format($0.balance)) }
            .joined(separator: "\n")

        return [payerText, receiverText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var settlementDetailedMessage: String {
        let balances = personBalances()
        guard !balances.isEmpty else { return L10n.text("settlement.detail.empty") }

        let total = totalAll
        let peopleCount = state.people.count
        let epsilon = 0.01
        let usingScale = state.settings.splitMode == .automaticScale && positiveScaleTotal > 0
        let totalScale = positiveScaleTotal

        var lines: [String] = []
        lines.append(L10n.text("settlement.detail.title"))
        lines.append(L10n.format("settlement.detail.total", format(total)))

        if usingScale {
            lines.append(
                L10n.format(
                    "settlement.detail.mode.scale",
                    decimal(totalScale)
                )
            )
        } else {
            lines.append(
                L10n.format(
                    "settlement.detail.mode.equal",
                    peopleCount
                )
            )
        }

        for (index, person) in state.people.enumerated() {
            let paid = totalPaid(for: person.id)
            let fairShare = share(for: person.id)
            let balance = paid - fairShare

            lines.append("")
            lines.append(L10n.format("settlement.detail.person.header", person.name))
            lines.append(L10n.format("settlement.detail.person.paid", format(paid)))

            if usingScale {
                lines.append(
                    L10n.format(
                        "settlement.detail.person.shareScale",
                        format(total),
                        decimal(max(0, person.scale)),
                        decimal(totalScale),
                        format(fairShare)
                    )
                )
            } else {
                lines.append(
                    L10n.format(
                        "settlement.detail.person.shareEqual",
                        format(total),
                        peopleCount,
                        format(fairShare)
                    )
                )
            }

            if abs(balance) <= epsilon {
                lines.append(
                    L10n.format(
                        "settlement.detail.person.balance.neutral",
                        format(paid),
                        format(fairShare)
                    )
                )
            } else if balance < 0 {
                lines.append(
                    L10n.format(
                        "settlement.detail.person.balance.owes",
                        format(paid),
                        format(fairShare),
                        format(abs(balance))
                    )
                )
            } else {
                lines.append(
                    L10n.format(
                        "settlement.detail.person.balance.receives",
                        format(paid),
                        format(fairShare),
                        format(balance)
                    )
                )
            }

            if index == state.people.count - 1 {
                lines.append("")
            }
        }

        lines.append(L10n.text("settlement.detail.result.title"))
        lines.append(settlementMessage)

        return lines.joined(separator: "\n")
    }

    func totalPaid(for personId: UUID) -> Double {
        guard let person = state.people.first(where: { $0.id == personId }) else { return 0 }
        return person.payments.reduce(0) { $0 + $1.amount }
    }

    func paymentCount(for personId: UUID) -> Int {
        guard let person = state.people.first(where: { $0.id == personId }) else { return 0 }
        return person.payments.count
    }

    func share(for personId: UUID) -> Double {
        guard let person = state.people.first(where: { $0.id == personId }) else { return 0 }

        if state.settings.splitMode == .equal50 {
            guard !state.people.isEmpty else { return 0 }
            return totalAll / Double(state.people.count)
        }

        let totalScale = positiveScaleTotal
        if totalScale <= 0 {
            guard !state.people.isEmpty else { return 0 }
            return totalAll / Double(state.people.count)
        }

        return totalAll * (max(0, person.scale) / totalScale)
    }

    func splitPct(for personId: UUID) -> Double {
        guard state.people.contains(where: { $0.id == personId }) else { return 0 }

        if state.settings.splitMode == .equal50 {
            guard !state.people.isEmpty else { return 0 }
            return 100 / Double(state.people.count)
        }

        let totalScale = positiveScaleTotal
        if totalScale <= 0 {
            guard !state.people.isEmpty else { return 0 }
            return 100 / Double(state.people.count)
        }

        guard let person = state.people.first(where: { $0.id == personId }) else { return 0 }
        return (max(0, person.scale) / totalScale) * 100
    }

    func addPerson() {
        let nextNumber = state.people.count + 1
        state.people.append(PersonData(name: L10n.format("store.addPerson.name", nextNumber), income: 0, scale: 1))
        save()
    }

    func removePeople(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            state.people.remove(at: index)
        }
        save()
    }

    func addPayment(for personId: UUID, description: String, amount: Double) {
        guard amount > 0 else { return }
        guard let index = state.people.firstIndex(where: { $0.id == personId }) else { return }

        let newPayment = Payment(description: description.isEmpty ? L10n.text("store.default.expense") : description, amount: amount)
        state.people[index].payments.append(newPayment)
        save()
    }

    func loadSampleData() {
        let currentSettings = state.settings

        state = AmorEContasState(
            people: [
                PersonData(
                    name: L10n.text("store.default.personA"),
                    income: 0,
                    scale: 2.5,
                    payments: [
                        Payment(description: "Dinner", amount: 48.50),
                        Payment(description: "Rent", amount: 950.00),
                        Payment(description: "Groceries", amount: 136.20),
                        Payment(description: "Internet", amount: 49.90),
                        Payment(description: "Pharmacy", amount: 27.35),
                        Payment(description: "Weekend trip gas", amount: 64.80)
                    ]
                ),
                PersonData(
                    name: L10n.text("store.default.personB"),
                    income: 0,
                    scale: 1.5,
                    payments: [
                        Payment(description: "Utilities", amount: 82.40),
                        Payment(description: "Streaming", amount: 15.99),
                        Payment(description: "Takeout", amount: 31.60),
                        Payment(description: "House supplies", amount: 42.15),
                        Payment(description: "Coffee beans", amount: 18.20)
                    ]
                ),
                PersonData(
                    name: L10n.format("store.addPerson.name", 3),
                    income: 0,
                    scale: 1,
                    payments: [
                        Payment(description: "Taxi", amount: 22.70),
                        Payment(description: "Movie tickets", amount: 29.00),
                        Payment(description: "Snacks", amount: 12.45),
                        Payment(description: "Brunch", amount: 54.30)
                    ]
                )
            ],
            settings: currentSettings
        )

        save()
    }

    func removePayments(for personId: UUID, at offsets: IndexSet) {
        guard let index = state.people.firstIndex(where: { $0.id == personId }) else { return }

        for offset in offsets.sorted(by: >) {
            state.people[index].payments.remove(at: offset)
        }

        save()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save AmorEContasState: \(error)")
        }
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            var decoded = try JSONDecoder().decode(AmorEContasState.self, from: data)
            if decoded.people.isEmpty {
                decoded.people = AmorEContasState.default.people
            }
            state = decoded
        } catch {
            state = .default
        }
    }

    func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = state.settings.currencySymbol
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(state.settings.currencySymbol) 0.00"
    }

    private func personBalances() -> [(person: PersonData, balance: Double)] {
        state.people.map { person in
            let paid = person.payments.reduce(0) { $0 + $1.amount }
            let fairShare = share(for: person.id)
            return (person: person, balance: paid - fairShare)
        }
    }

    private func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private var fileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("love-ledger-state.json")
    }
}
