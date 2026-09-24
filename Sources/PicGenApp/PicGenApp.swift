import SwiftUI

@main
struct PicGenApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var library = Library()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(library)
        }
    }
}
