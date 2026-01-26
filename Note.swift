import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var text: String
    var creationDate: Date
    
    init(id: UUID = UUID(), title: String, text: String, creationDate: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.creationDate = creationDate
    }
}
