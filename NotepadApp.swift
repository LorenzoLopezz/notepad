import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: autosaveNotification, object: nil)
        return .terminateNow
    }
}

@main
struct NotepadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.newNoteAction) private var newNoteAction
    @FocusedValue(\.resetContentAction) private var resetContentAction
    @FocusedValue(\.saveNowAction) private var saveNowAction

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
            CommandGroup(replacing: .saveItem) {
                Button("Guardar") {
                    saveNowAction?()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(saveNowAction == nil)
            }
            CommandGroup(replacing: .importExport) { }
        }
    }
}
