import SwiftUI

@main
struct LumaGradeApp: App {
    @StateObject private var library = ProjectLibrary()

    var body: some Scene {
        WindowGroup { RootView().environmentObject(library) }
    }
}
