import SwiftData
import SwiftUI

@main
struct AIWindowApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                TopicRecord.self,
                SearchRecord.self,
            ])
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}
