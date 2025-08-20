//
//  StoreKitManager.swift
import Foundation
import StoreKit
import SwiftUI

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    @Published var fullUnlocked: Bool = false
    @Published var product: Product? = nil
    @Published var isPurchasing: Bool = false
    @Published var lastError: String? = nil

    static let fullUnlockID = "com.example.repgoal.fullunlock" // TODO: replace

    private init() {}

    func configure() async {
        await self.updateEntitlements()
        await self.loadProducts()
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.fullUnlockID])
            self.product = products.first
        } catch {
            self.lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    private func handle(transactionResult: VerificationResult<StoreKit.Transaction>) async {
        switch transactionResult {
        case .unverified: break
        case .verified(let tx):
            if tx.productID == Self.fullUnlockID { self.fullUnlocked = true }
            await tx.finish()
        }
    }

    func updateEntitlements() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let tx):
                if tx.productID == Self.fullUnlockID { self.fullUnlocked = true }
            case .unverified: continue
            }
        }
    }

    func purchaseFullUnlock() async -> Bool {
        guard let product else { self.lastError = "Product not loaded"; return false }
        self.isPurchasing = true; defer { isPurchasing = false }
        do {
            let res = try await product.purchase()
            switch res {
            case .success(let v):
                switch v {
                case .verified(let tx):
                    if tx.productID == Self.fullUnlockID { self.fullUnlocked = true }
                    await tx.finish()
                    return true
                case .unverified(_, let err):
                    self.lastError = err.localizedDescription
                    return false
                }
            case .userCancelled: return false
            case .pending: return false
            @unknown default: return false
            }
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { self.lastError = error.localizedDescription }
        await self.updateEntitlements()
    }
}
