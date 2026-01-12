import SwiftUI

@main
struct NotepadApp: App {
    @FocusedValue(\.newNoteAction) private var newNoteAction
    @FocusedValue(\.resetContentAction) private var resetContentAction

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
            CommandGroup(after: .newItem) {
                Button("Restablecer contenido") {
                    resetContentAction?()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(resetContentAction == nil)
            }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .importExport) { }
        }
    }
}
