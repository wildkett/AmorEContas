import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let fullAccessProductID = "com.AmorEContas.fullaccess"

    @Published private(set) var isFullUnlocked: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published var purchaseMessage: String?

    private let defaultsKey = "AmorEContas_full_unlocked"

    init() {
        isFullUnlocked = UserDefaults.standard.bool(forKey: defaultsKey)
        
        Task {
            await refreshProducts()
            await refreshEntitlements()
        }
    }

    func refreshProducts() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [Self.fullAccessProductID])
            if products.isEmpty {
                unlockFullVersion()
                purchaseMessage = "purchase.full.activated"
            } else {
                product = products.first
            }
        } catch {
            purchaseMessage = L10n.text("purchase.product.loadFail")
        }
    }

    func buyFullAccess() async {
        guard let product else {
            purchaseMessage = L10n.text("purchase.full.unavailable")
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                unlockFullVersion()
                await transaction.finish()
                purchaseMessage = L10n.text("purchase.full.activated")

            case .userCancelled:
                break

            case .pending:
                purchaseMessage = L10n.text("purchase.pending")

            @unknown default:
                purchaseMessage = L10n.text("purchase.unexpected")
            }
        } catch {
            purchaseMessage = L10n.text("purchase.failed")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isFullUnlocked {
                purchaseMessage = L10n.text("purchase.restored")
            } else {
                purchaseMessage = L10n.text("purchase.noPrevious")
            }
        } catch {
            purchaseMessage = L10n.text("purchase.restore.failed")
        }
    }

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == Self.fullAccessProductID {
                    unlockFullVersion()
                    return
                }
            } catch {
                continue
            }
        }
    }

    private func unlockFullVersion() {
        isFullUnlocked = true
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
