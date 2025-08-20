//
//  UpgradeView.swift (v17)
import StoreKit
import SwiftData
import SwiftUI

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsArray: [AppSettings]
    @StateObject private var store = StoreKitManager.shared

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "crown.fill").font(.system(size: 52))
                Text("Unlock RepGoal Pro").font(.title2).bold()
                Text("Create unlimited goals and Macro Plans.\nSupport development and get more features.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Group {
                    if let p = store.product {
                        Text("One‑time purchase • \(p.displayPrice)").font(.headline)
                    } else { Text("Loading price…").foregroundStyle(.secondary) }
                }.padding(.top, 8)

                Button {
                    Task {
                        let ok = await store.purchaseFullUnlock()
                        if ok {
                            settings.hasFullUnlock = true
                            try? context.save()
                            dismiss()
                        }
                    }
                } label: {
                    HStack { if store.isPurchasing { ProgressView() }; Text(store.fullUnlocked ? "Unlocked" : "Buy Full Version") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isPurchasing || store.fullUnlocked)

                Button("Restore Purchases") {
                    Task {
                        await store.restore()
                        if store.fullUnlocked {
                            settings.hasFullUnlock = true
                            try? context.save()
                            dismiss()
                        }
                    }
                }.buttonStyle(.bordered)

                if let err = store.lastError {
                    Text(err).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Upgrade")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
        .task { await store.configure() }
    }
}

#Preview {
    UpgradeView()
        .modelContainer(for: AppSettings.self)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environmentObject(StoreKitManager.shared)
        .previewDisplayName("Upgrade View")
}
