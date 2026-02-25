//
//  AmorEContasApp.swift
//  AmorEContas
//
//  Created by Kett Lima on 16/02/26.
//

import SwiftUI

@main
struct AmorEContasApp: App {
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
        }
    }
}
