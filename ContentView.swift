import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("notepadText") private var text: String = ""
    @AppStorage("notepadFontSize") private var fontSize: Double = 16

    private let minFontSize: Double = 10
    private let maxFontSize: Double = 36

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: fontSize))
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .toolbar {
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
    }

    private func decreaseFont() {
        fontSize = max(minFontSize, fontSize - 1)
    }

    private func increaseFont() {
        fontSize = min(maxFontSize, fontSize + 1)
    }
}
