import SwiftUI

@main
struct NotepadApp: App {
    @FocusedValue(\.newNoteAction) private var newNoteAction

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 480)
        }
        .commands {
            // The app saves automatically, so file commands are not needed.
            CommandGroup(replacing: .newItem) {
                Button("Nueva nota") {
                    newNoteAction?()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .importExport) { }
        }
    }
}
