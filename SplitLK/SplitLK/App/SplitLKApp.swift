//
//  SplitLKApp.swift
//  SplitLK
//
//  Created by COBSCCOPM251P-031 on 2026-10-26.
//

import SwiftUI
import CoreData

@main
struct SplitLKApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
