import AppKit
import SwiftUI
import UniformTypeIdentifiers

let autosaveNotification = Notification.Name("NotepadAutosaveNow")

struct MarkdownPreviewView: NSViewRepresentable {
    let text: String
    let baseFontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let rendered = MarkdownPreviewRenderer.render(text: text, baseFontSize: baseFontSize)
        textView.textStorage?.setAttributedString(rendered)
    }
}

private enum MarkdownPreviewRenderer {
    static func render(text: String, baseFontSize: Double) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(
                string: "Sin contenido",
                attributes: placeholderAttributes(baseFontSize: baseFontSize)
            )
        }

        let result = NSMutableAttributedString()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var paragraphBuffer: [String] = []
        var codeBlockLines: [String] = []
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let paragraphText = paragraphBuffer.joined(separator: " ")
            result.append(paragraph(paragraphText, baseFontSize: baseFontSize))
            paragraphBuffer.removeAll()
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                flushParagraph()
                if isInsideCodeBlock {
                    result.append(codeBlock(codeBlockLines.joined(separator: "\n"), baseFontSize: baseFontSize))
                    codeBlockLines.removeAll()
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = headingMatch(for: line) {
                flushParagraph()
                result.append(headingBlock(level: heading.level, text: heading.text, baseFontSize: baseFontSize))
                continue
            }

            if isHorizontalRule(trimmedLine) {
                flushParagraph()
                result.append(horizontalRule(baseFontSize: baseFontSize))
                continue
            }

            if let listItem = listMatch(for: line) {
                flushParagraph()
                result.append(listBlock(marker: listItem.marker, text: listItem.text, indentLevel: listItem.indentLevel, ordered: listItem.ordered, baseFontSize: baseFontSize))
                continue
            }

            if let quoteText = quoteMatch(for: line) {
                flushParagraph()
                result.append(blockQuote(quoteText, baseFontSize: baseFontSize))
                continue
            }

            paragraphBuffer.append(trimmedLine)
        }

        flushParagraph()

        if isInsideCodeBlock, !codeBlockLines.isEmpty {
            result.append(codeBlock(codeBlockLines.joined(separator: "\n"), baseFontSize: baseFontSize))
        }

        return result
    }

    private static func placeholderAttributes(baseFontSize: Double) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    private static func paragraph(_ text: String, baseFontSize: Double) -> NSAttributedString {
        attributedInlineText(
            text,
            attributes: blockAttributes(
                font: .systemFont(ofSize: baseFontSize),
                color: .labelColor,
                lineSpacing: 3,
                paragraphSpacing: 7
            ),
            baseFontSize: baseFontSize
        )
    }

    private static func headingBlock(level: Int, text: String, baseFontSize: Double) -> NSAttributedString {
        let sizeMap: [CGFloat] = [
            max(baseFontSize + 16, 28),
            max(baseFontSize + 10, 24),
            max(baseFontSize + 6, 21),
            max(baseFontSize + 3, 18),
            max(baseFontSize + 1, 16),
            baseFontSize
        ]
        let fontSize = sizeMap[min(max(level - 1, 0), sizeMap.count - 1)]
        return attributedInlineText(
            text,
            attributes: blockAttributes(
                font: .systemFont(ofSize: fontSize, weight: .bold),
                color: .labelColor,
                lineSpacing: 2,
                paragraphSpacing: 9
            ),
            baseFontSize: baseFontSize
        )
    }

    private static func listBlock(marker: String, text: String, indentLevel: Int, ordered: Bool, baseFontSize: Double) -> NSAttributedString {
        let indent = CGFloat(18 + (indentLevel * 16))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.5
        paragraphStyle.paragraphSpacing = 5
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.headIndent = indent + 18
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]

        let prefix = ordered ? "\(marker)\t" : "•\t"
        let result = NSMutableAttributedString(
            string: prefix,
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        result.append(
            attributedInlineText(
                text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseFontSize),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle
                ],
                baseFontSize: baseFontSize,
                appendSpacing: true
            )
        )
        return result
    }

    private static func blockQuote(_ text: String, baseFontSize: Double) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.5
        paragraphStyle.paragraphSpacing = 7
        paragraphStyle.firstLineHeadIndent = 16
        paragraphStyle.headIndent = 16

        let quote = NSMutableAttributedString(
            string: "▍ ",
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize + 2, weight: .bold),
                .foregroundColor: NSColor.controlAccentColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        quote.append(
            attributedInlineText(
                text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraphStyle,
                    .obliqueness: 0.1
                ],
                baseFontSize: baseFontSize,
                appendSpacing: true
            )
        )
        return quote
    }

    private static func codeBlock(_ text: String, baseFontSize: Double) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.firstLineHeadIndent = 16
        paragraphStyle.headIndent = 16

        return NSAttributedString(
            string: text + "\n\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: max(baseFontSize - 1, 12), weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.controlBackgroundColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private static func horizontalRule(baseFontSize: Double) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: "────────────\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: max(baseFontSize - 1, 12), weight: .medium),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private static func blockAttributes(
        font: NSFont,
        color: NSColor,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func attributedInlineText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        baseFontSize: Double,
        appendSpacing: Bool = true
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsText = text as NSString
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)|`([^`\n]+)`|\*\*([^*]+)\*\*|__([^_]+)__|(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        var currentLocation = 0
        for match in matches {
            if match.range.location > currentLocation {
                let plain = nsText.substring(with: NSRange(location: currentLocation, length: match.range.location - currentLocation))
                result.append(NSAttributedString(string: plain, attributes: attributes))
            }

            if match.range(at: 1).location != NSNotFound, match.range(at: 2).location != NSNotFound {
                let label = nsText.substring(with: match.range(at: 1))
                let href = nsText.substring(with: match.range(at: 2))
                var linkAttributes = attributes
                linkAttributes[.link] = href
                linkAttributes[.foregroundColor] = NSColor.controlAccentColor
                linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                result.append(attributedInlineText(label, attributes: linkAttributes, baseFontSize: baseFontSize, appendSpacing: false))
            } else if match.range(at: 3).location != NSNotFound {
                let code = nsText.substring(with: match.range(at: 3))
                var codeAttributes = attributes
                codeAttributes[.font] = NSFont.monospacedSystemFont(ofSize: max(baseFontSize - 1, 12), weight: .regular)
                codeAttributes[.backgroundColor] = NSColor.controlBackgroundColor
                result.append(NSAttributedString(string: code, attributes: codeAttributes))
            } else if match.range(at: 4).location != NSNotFound || match.range(at: 5).location != NSNotFound {
                let range = match.range(at: 4).location != NSNotFound ? match.range(at: 4) : match.range(at: 5)
                let boldText = nsText.substring(with: range)
                var boldAttributes = attributes
                boldAttributes[.font] = makeFont(from: attributes[.font] as? NSFont, baseFontSize: baseFontSize, weight: .bold)
                result.append(attributedInlineText(boldText, attributes: boldAttributes, baseFontSize: baseFontSize, appendSpacing: false))
            } else if match.range(at: 6).location != NSNotFound || match.range(at: 7).location != NSNotFound {
                let range = match.range(at: 6).location != NSNotFound ? match.range(at: 6) : match.range(at: 7)
                let italicText = nsText.substring(with: range)
                var italicAttributes = attributes
                italicAttributes[.font] = makeItalicFont(from: attributes[.font] as? NSFont, baseFontSize: baseFontSize)
                result.append(attributedInlineText(italicText, attributes: italicAttributes, baseFontSize: baseFontSize, appendSpacing: false))
            }

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsText.length {
            let trailing = nsText.substring(from: currentLocation)
            result.append(NSAttributedString(string: trailing, attributes: attributes))
        }

        if appendSpacing {
            result.append(NSAttributedString(string: "\n\n", attributes: attributes))
        }

        return result
    }

    private static func makeFont(from current: NSFont?, baseFontSize: Double, weight: NSFont.Weight) -> NSFont {
        let size = current?.pointSize ?? CGFloat(baseFontSize)
        return .systemFont(ofSize: size, weight: weight)
    }

    private static func makeItalicFont(from current: NSFont?, baseFontSize: Double) -> NSFont {
        let size = current?.pointSize ?? CGFloat(baseFontSize)
        return NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }

    private static func headingMatch(for line: String) -> (level: Int, text: String)? {
        let nsLine = line as NSString
        let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#)
        guard
            let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
            match.numberOfRanges == 3
        else {
            return nil
        }

        let level = nsLine.substring(with: match.range(at: 1)).count
        let text = nsLine.substring(with: match.range(at: 2))
        return (level, text)
    }

    private static func listMatch(for line: String) -> (marker: String, text: String, indentLevel: Int, ordered: Bool)? {
        let nsLine = line as NSString
        let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s+(.+)$"#)
        guard
            let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
            match.numberOfRanges == 4
        else {
            return nil
        }

        let indentation = nsLine.substring(with: match.range(at: 1)).count / 2
        let marker = nsLine.substring(with: match.range(at: 2))
        let text = nsLine.substring(with: match.range(at: 3))
        let ordered = marker.range(of: #"\d+\."#, options: .regularExpression) != nil
        return (marker, text, indentation, ordered)
    }

    private static func quoteMatch(for line: String) -> String? {
        let nsLine = line as NSString
        let regex = try? NSRegularExpression(pattern: #"^>\s?(.*)$"#)
        guard
            let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
            match.numberOfRanges == 2
        else {
            return nil
        }

        return nsLine.substring(with: match.range(at: 1))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.range(of: #"^(\*\s*\*\s*\*|-{3,}|_{3,})$"#, options: .regularExpression) != nil
    }
}

struct NewNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ResetContentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SaveNowActionKey: FocusedValueKey {
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

    var saveNowAction: (() -> Void)? {
        get { self[SaveNowActionKey.self] }
        set { self[SaveNowActionKey.self] = newValue }
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
    @AppStorage("notepadMarkdownPreviewEnabled") private var markdownPreviewEnabled = false

    @State private var tabs: [Note] = []
    @State private var selectedTabID: UUID? = nil
    @State private var hasLoaded = false
    @State private var showDeleteAlert = false
    @State private var autosaveWorkItem: DispatchWorkItem?

    private let autosaveInterval: TimeInterval = 5
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
        .focusedValue(\.saveNowAction, manualSave)
        .toolbar { toolbarContent }
        .onAppear(perform: loadTabsIfNeeded)
        .onReceive(NotificationCenter.default.publisher(for: autosaveNotification)) { _ in
            saveAllTabs()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
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
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        for tab in tabs {
            NotePersistence.shared.save(tab)
        }
    }

    private func manualSave() {
        saveAllTabs()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            saveAllTabs()
        }

        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveInterval, execute: workItem)
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
            HStack(alignment: .center, spacing: 10) {
                Toggle(isOn: $markdownPreviewEnabled) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .help(markdownPreviewEnabled ? "Cambiar a edición" : "Cambiar a vista Markdown")

                TextField("Título", text: bindingForTitle(selectedTabID))
                    .textFieldStyle(.plain)
                    .font(.system(size: max(fontSize + 8, 24), weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Text(markdownPreviewEnabled ? "Vista Markdown" : "Edición")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            Divider()
                .padding(.horizontal, 12)

            if markdownPreviewEnabled {
                MarkdownPreviewView(
                    text: tabs.first(where: { $0.id == selectedTabID })?.text ?? "",
                    baseFontSize: fontSize
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                NormalizedTextEditor(
                    text: bindingForText(selectedTabID),
                    fontSize: fontSize,
                    normalize: normalizeApostrophes
                )
                .id(selectedTabID) // Force recreation when switching tabs
                .padding(12)
            }
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

                Button(action: manualSave) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Guardar ahora")
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
                scheduleAutosave()
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
                scheduleAutosave()
            }
        )
    }

    private func normalizeApostrophes(in text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

}
