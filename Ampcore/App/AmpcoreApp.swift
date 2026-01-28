import SwiftUI
import CoreData
import UIKit

@main
struct AmpcoreApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var env = AppEnvironment.shared
    
    init() {
        // Stabilize TabBar blur so it does not change based on content behind it.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        // Small tint prevents perceived "jump" when background content updates.
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.10)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.18)
        
        let tabBar = UITabBar.appearance()
        tabBar.isTranslucent = true
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
    
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
