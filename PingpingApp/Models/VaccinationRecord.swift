import Foundation
import SwiftData

/// 一次疫苗接种记录。ownerID 关联 DogProfile，保留为可选值以兼容早期数据。
@Model
final class VaccinationRecord {
    var id: UUID
    var vaccineName: String
    var date: Date
    var nextDueDate: Date?
    var note: String
    var ownerID: String?
    var createdAt: Date

    init(
        vaccineName: String,
        date: Date,
        nextDueDate: Date? = nil,
        note: String = "",
        ownerID: String? = nil
    ) {
        self.id = UUID()
        self.vaccineName = vaccineName
        self.date = date
        self.nextDueDate = nextDueDate
        self.note = note
        self.ownerID = ownerID
        self.createdAt = .now
    }
}
