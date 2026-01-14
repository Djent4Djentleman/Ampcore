import SwiftUI
import CoreData

@main
struct AmpcoreApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var env = AppEnvironment.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(env)
                .preferredColorScheme(env.settings.colorScheme)
                .onAppear {
                    env.autoScanIfNeeded(context: persistence.container.viewContext)
                }
        }
    }
}
