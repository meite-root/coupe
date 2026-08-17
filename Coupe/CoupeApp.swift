//
//  CoupeApp.swift
//  Coupe
//
//  Created by Hassane Meite on 8/17/26.
//

import SwiftUI
import SwiftData

@main
struct CoupeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MediaProject.self,
            Clip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            preconditionFailure("Could not create Coupe's data store: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(sharedModelContainer)
    }
}
