import SwiftUI

@main
struct LUTStudioOfflineApp: App {
    var body: some Scene {
        WindowGroup {
            ProjectsHomeView()
                .preferredColorScheme(.dark)
        }
    }
}
