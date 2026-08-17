import Combine
import Foundation
import StoreKit

@MainActor
final class StoreKitPurchaseStore: ObservableObject {
    static let monthlyProductId = "blanked_monthly_299"
    static let annualProductId = "blanked_annual_19"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasLoadedProducts = false
    @Published var message: String?

    private let productIds = [monthlyProductId, annualProductId]

    var hasEntitlement: Bool {
        !purchasedProductIds.isEmpty
    }

    var annualProduct: Product? {
        product(for: Self.annualProductId)
    }

    var monthlyProduct: Product? {
        product(for: Self.monthlyProductId)
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoadedProducts = true
        }

        do {
            let loadedProducts = try await Product.products(for: productIds)
            products = loadedProducts.sorted { first, second in
                (productIds.firstIndex(of: first.id) ?? 0) < (productIds.firstIndex(of: second.id) ?? 0)
            }
            message = loadedProducts.isEmpty ? "Subscriptions are not available yet." : nil
        } catch {
            message = "Could not load subscriptions."
        }

        await updateCustomerProductStatus()
    }

    func purchase(productId: String) async -> Bool {
        if products.isEmpty {
            await loadProducts()
        }

        guard let product = product(for: productId) else {
            message = "This subscription is not available yet."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateCustomerProductStatus()
                message = nil
                return true
            case .userCancelled:
                message = "Purchase cancelled."
                return false
            case .pending:
                message = "Purchase pending approval."
                return false
            @unknown default:
                message = "Purchase could not be completed."
                return false
            }
        } catch {
            message = "Purchase could not be completed."
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
            message = hasEntitlement ? "Purchase restored." : "No active subscription found."
        } catch {
            message = "Could not restore purchases."
        }
    }

    func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await transaction.finish()
            await updateCustomerProductStatus()
        }
    }

    func priceText(for productId: String, fallback: String) -> String {
        if let displayPrice = product(for: productId)?.displayPrice {
            return displayPrice
        }
        return hasLoadedProducts ? fallback : "Loading..."
    }

    private func product(for productId: String) -> Product? {
        products.first { $0.id == productId }
    }

    private func updateCustomerProductStatus() async {
        var activeProductIds = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard productIds.contains(transaction.productID) else { continue }
            activeProductIds.insert(transaction.productID)
        }

        purchasedProductIds = activeProductIds
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreKitPurchaseError.failedVerification
        }
    }
}

private enum StoreKitPurchaseError: Error {
    case failedVerification
}
