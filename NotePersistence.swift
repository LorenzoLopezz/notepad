import Foundation

class NotePersistence {
    static let shared = NotePersistence()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var notesDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Notes")
    }
    
    private init() {
        createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        guard let url = notesDirectory else { return }
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func getFileURL(for note: Note) -> URL? {
        guard let directory = notesDirectory else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: note.creationDate)
        // Append part of UUID to ensure uniqueness if created at same second
        let filename = "\(timestamp)_\(note.id.uuidString.prefix(4)).json"
        return directory.appendingPathComponent(filename)
    }
    
    func save(_ note: Note) {
        guard let url = getFileURL(for: note) else { return }
        do {
            let data = try encoder.encode(note)
            try data.write(to: url)
        } catch {
            print("Error saving note: \(error)")
        }
    }
    
    func loadAll() -> [Note] {
        guard let directory = notesDirectory else { return [] }
        var notes: [Note] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for url in fileURLs where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url),
                   let note = try? decoder.decode(Note.self, from: data) {
                    notes.append(note)
                }
            }
        } catch {
            print("Error loading notes: \(error)")
        }
        
        return notes.sorted(by: { $0.creationDate < $1.creationDate })
    }
    
    func delete(_ note: Note) {
        guard let url = getFileURL(for: note) else { return }
        try? fileManager.removeItem(at: url)
    }
}
