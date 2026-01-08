import SwiftUI
import CoreData

@main
struct AmpcoreApp: App {
    let persistence = PersistenceController.shared
    let env = AppEnvironment.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(env)
                .onAppear {
                    env.autoScanIfNeeded(context: persistence.container.viewContext)
                }
        }
    }
}
