import AppKit
import SwiftUI

struct NoteTab: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var text: String
}

struct NewNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newNoteAction: (() -> Void)? {
        get { self[NewNoteActionKey.self] }
        set { self[NewNoteActionKey.self] = newValue }
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
        let parent: NormalizedTextEditor
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
    @AppStorage("notepadTabs") private var tabsData: Data = Data()
    @AppStorage("notepadSelectedTabID") private var selectedTabIDString: String = ""
    @AppStorage("notepadFontSize") private var fontSize: Double = 16

    @State private var tabs: [NoteTab] = []
    @State private var selectedTabID: UUID? = nil
    @State private var hasLoaded = false
    @State private var showDeleteAlert = false

    private let minFontSize: Double = 10
    private let maxFontSize: Double = 36
    private let maxTitleLength = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTabID {
                TextField("Titulo", text: bindingForTitle(selectedTabID))
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
                .padding(12)
            } else {
                Text("Sin pestanas")
                    .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusedValue(\.newNoteAction, addTab)
        .toolbar {
            ToolbarItem {
                Picker("Pestañas", selection: $selectedTabID) {
                    ForEach(tabs) { tab in
                        Text(displayTitle(tab.title))
                            .tag(Optional(tab.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 160)
            }

            ToolbarItemGroup {
                Button(action: addTab) {
                    Image(systemName: "plus")
                }
                .help("Nueva pestaña")

                Button(action: requestDeleteTab) {
                    Image(systemName: "trash")
                }
                .help("Cerrar pestaña")
                .disabled(tabs.count <= 1)
            }

            ToolbarItemGroup {
                Button(action: decreaseFont) {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Disminuir tamano")

                Button(action: increaseFont) {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Aumentar tamano")
            }
        }
        .onAppear(perform: loadTabsIfNeeded)
        .onChange(of: tabs) { _ in
            saveTabs()
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
            Text("Se perdera el contenido de esta pestaña")
        }
    }

    private func decreaseFont() {
        fontSize = max(minFontSize, fontSize - 1)
    }

    private func increaseFont() {
        fontSize = min(maxFontSize, fontSize + 1)
    }

    private func displayTitle(_ title: String) -> String {
        let trimmed = title.isEmpty ? "Sin titulo" : title
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

        if let decoded = decodeTabs(from: tabsData), !decoded.isEmpty {
            tabs = decoded
        } else {
            tabs = [NoteTab(id: UUID(), title: "Nota 1", text: "")]
        }

        if let restoredID = UUID(uuidString: selectedTabIDString),
          tabs.contains(where: { $0.id == restoredID }) {
            selectedTabID = restoredID
        } else {
            selectedTabID = tabs.first?.id
        }
    }

    private func saveTabs() {
        if let data = try? JSONEncoder().encode(tabs) {
            tabsData = data
        }
    }

    private func decodeTabs(from data: Data) -> [NoteTab]? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([NoteTab].self, from: data)
    }

    private func addTab() {
        let newTab = NoteTab(id: UUID(), title: "Nota \(tabs.count + 1)", text: "")
        tabs.append(newTab)
        selectedTabID = newTab.id
    }

    private func removeSelectedTab() {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }

        tabs.remove(at: index)
        if tabs.isEmpty {
            let fallback = NoteTab(id: UUID(), title: "Nota 1", text: "")
            tabs = [fallback]
            self.selectedTabID = fallback.id
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
                    return
                }
                tabs[index].title = normalized
            }
        )
    }

    private func normalizeApostrophes(in text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

}
