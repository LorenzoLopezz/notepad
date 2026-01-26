import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NewNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ResetContentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newNoteAction: (() -> Void)? {
        get { self[NewNoteActionKey.self] }
        set { self[NewNoteActionKey.self] = newValue }
    }

    var resetContentAction: (() -> Void)? {
        get { self[ResetContentActionKey.self] }
        set { self[ResetContentActionKey.self] = newValue }
    }
}

final class NormalizedTextView: NSTextView {
    var normalize: (String) -> String = { $0 }

    override func paste(_ sender: Any?) {
        if let string = NSPasteboard.general.string(forType: .string) {
            let normalized = normalize(string)
            insertText(normalized, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }
}

struct NormalizedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var normalize: (String) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NormalizedTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.normalize = normalize

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NormalizedTextView else { return }
        textView.normalize = normalize
        if Double(textView.font?.pointSize ?? 0) != fontSize {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NormalizedTextEditor
        var isUpdating = false

        init(_ parent: NormalizedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else {
                return
            }
            let normalized = parent.normalize(textView.string)
            if normalized != textView.string {
                isUpdating = true
                let selectedRanges = textView.selectedRanges
                textView.string = normalized
                textView.selectedRanges = selectedRanges
                isUpdating = false
            }
            if parent.text != normalized {
                parent.text = normalized
            }
        }
    }
}

struct ContentView: View {
    @AppStorage("notepadSelectedTabID") private var selectedTabIDString: String = ""
    @AppStorage("notepadFontSize") private var fontSize: Double = 16

    @State private var tabs: [Note] = []
    @State private var selectedTabID: UUID? = nil
    @State private var hasLoaded = false
    @State private var showDeleteAlert = false
    
    // Auto-save timer: 5 seconds
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private let minFontSize: Double = 10
    private let maxFontSize: Double = 36
    private let maxTitleLength = 40

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTabID {
                editorView(for: selectedTabID)
            } else {
                Text("Sin pestañas")
                    .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusedValue(\.newNoteAction, addTab)
        .focusedValue(\.resetContentAction, resetContent)
        .toolbar { toolbarContent }
        .onAppear(perform: loadTabsIfNeeded)
        .onReceive(timer) { _ in
            saveAllTabs()
        }
        .onChange(of: selectedTabID) { newValue in
            selectedTabIDString = newValue?.uuidString ?? ""
        }
        .alert("Eliminar pestaña", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                removeSelectedTab()
            }
        } message: {
            Text("Se perderá el contenido de esta pestaña de forma permanente.")
        }
    }
    
    private func saveAllTabs() {
        for tab in tabs {
            NotePersistence.shared.save(tab)
        }
    }

    private func resetContent() {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }
        tabs[index].text = ""
        tabs[index].title = ""
        // Immediate save on reset
        NotePersistence.shared.save(tabs[index])
    }

    private func editorView(for selectedTabID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: bindingForTitle(selectedTabID))
                .textFieldStyle(.plain)
                .font(.system(size: max(fontSize + 8, 24), weight: .bold))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Divider()
                .padding(.horizontal, 12)

            NormalizedTextEditor(
                text: bindingForText(selectedTabID),
                fontSize: fontSize,
                normalize: normalizeApostrophes
            )
            .id(selectedTabID) // Force recreation when switching tabs
            .padding(12)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Pestañas", selection: $selectedTabID) {
                ForEach(tabs) { tab in
                    Text(displayTitle(tab.title))
                        .tag(Optional(tab.id))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 60, maxWidth: 100)
        }

        ToolbarItemGroup {
            HStack {
                Button(action: addTab) {
                    Image(systemName: "plus")
                }
                .help("Nueva pestaña")

                Button(action: requestDeleteTab) {
                    Image(systemName: "trash")
                }
                .help("Cerrar pestaña")
                .disabled(tabs.count <= 1)

                Button(action: decreaseFont) {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Disminuir tamaño")

                Button(action: increaseFont) {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Aumentar tamaño")

                Button(action: exportCurrentTab) {
                    Image(systemName: "externaldrive")
                }
                .help("Exportar")
                .disabled(selectedTabID == nil)
            }
            .frame(minWidth: 60, alignment: .leading)
        }
    }

    private func decreaseFont() {
        fontSize = max(minFontSize, fontSize - 1)
    }

    private func increaseFont() {
        fontSize = min(maxFontSize, fontSize + 1)
    }

    private func exportCurrentTab() {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFileName(tab.title)).txt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try tab.text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("No se pudo exportar la nota: \(error)")
            }
        }
    }

    private func safeFileName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "nota"
        }
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "nota" : cleaned
    }

    private func displayTitle(_ title: String) -> String {
        let trimmed = title.isEmpty ? "Sin título" : title
        if trimmed.count > 20 {
            let prefixText = String(trimmed.prefix(20))
            return "\(prefixText)..."
        }
        return trimmed
    }

    private func requestDeleteTab() {
        if tabs.count > 1 {
            showDeleteAlert = true
        }
    }

    private func loadTabsIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let loaded = NotePersistence.shared.loadAll()
        if !loaded.isEmpty {
            tabs = loaded
        } else {
            // Start with a new note if none exist
            let newNote = Note(title: "Nota 1", text: "")
            tabs = [newNote]
            NotePersistence.shared.save(newNote)
        }

        if let restoredID = UUID(uuidString: selectedTabIDString),
          tabs.contains(where: { $0.id == restoredID }) {
            selectedTabID = restoredID
        } else {
            selectedTabID = tabs.first?.id
        }
    }

    private func addTab() {
        let newTab = Note(title: "Nota \(tabs.count + 1)", text: "")
        tabs.append(newTab)
        selectedTabID = newTab.id
        NotePersistence.shared.save(newTab)
    }

    private func removeSelectedTab() {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }

        let noteToDelete = tabs[index]
        NotePersistence.shared.delete(noteToDelete)
        
        tabs.remove(at: index)
        if tabs.isEmpty {
            let fallback = Note(title: "Nota 1", text: "")
            tabs = [fallback]
            self.selectedTabID = fallback.id
            NotePersistence.shared.save(fallback)
        } else {
            let newIndex = min(index, tabs.count - 1)
            self.selectedTabID = tabs[newIndex].id
        }
    }

    private func bindingForText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { tabs.first(where: { $0.id == id })?.text ?? "" },
            set: { newValue in
                guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
                tabs[index].text = normalizeApostrophes(in: newValue)
                // Note: We don't save immediately here to avoid I/O thrashing; timer handles it.
                // However, for safety, one could save here too, but timer is requested.
            }
        )
    }

    private func bindingForTitle(_ id: UUID) -> Binding<String> {
        Binding(
            get: { tabs.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
                let normalized = normalizeApostrophes(in: newValue)
                if normalized.count > maxTitleLength {
                    tabs[index].title = String(normalized.prefix(maxTitleLength))
                } else {
                    tabs[index].title = normalized
                }
                // Similar to text, let the timer handle saving.
            }
        )
    }

    private func normalizeApostrophes(in text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

}