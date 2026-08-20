import SwiftUI
import SwiftData

struct VaccinationRecordsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \VaccinationRecord.date, order: .reverse) private var allRecords: [VaccinationRecord]

    let petName: String
    let ownerID: String

    @State private var showAddRecord = false

    private var records: [VaccinationRecord] {
        allRecords.filter { $0.ownerID == ownerID }
    }

    private var nextPlanText: String {
        guard let date = records.compactMap(\.nextDueDate).filter({ $0 >= .now }).min() else {
            return "暂无"
        }
        return date.formatted(.dateTime.month().day())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    recordsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("疫苗接种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddRecord = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(vaccineGreen)
                            .frame(width: 44, height: 44)
                            .background(vaccineGreen.opacity(0.12), in: Circle())
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            VaccinationRecordEditor(petName: petName, ownerID: ownerID)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 7) {
                Text("\(records.count)")
                    .font(.system(size: 28, weight: .semibold))
                Text("已接种")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 56)

            VStack(spacing: 7) {
                Text(nextPlanText)
                    .font(.system(size: 19, weight: .semibold))
                Text("下次计划")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var recordsSection: some View {
        VStack(spacing: 14) {
            HStack {
                Text("接种记录")
                    .font(.title3.bold())
                Spacer()
                Text("共 \(records.count) 条")
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "cross.vial")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(vaccineGreen)
                    Text("暂无接种记录")
                        .font(.headline)
                    Text("点击右上角添加 \(petName) 的第一条疫苗记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("记录疫苗") { showAddRecord = true }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(vaccineGreen, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 54)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(records) { record in
                        HStack(spacing: 14) {
                            Image(systemName: "syringe.fill")
                                .foregroundStyle(vaccineGreen)
                                .frame(width: 40, height: 40)
                                .background(vaccineGreen.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.vaccineName).font(.headline)
                                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let next = record.nextDueDate {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("下次")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(next.formatted(.dateTime.month().day()))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                context.delete(record)
                                try? context.save()
                            }
                        }
                    }
                }
            }
        }
    }

    private var vaccineGreen: Color { Color(red: 0.22, green: 0.78, blue: 0.48) }
}

private struct VaccinationRecordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let petName: String
    let ownerID: String

    @State private var vaccineName = ""
    @State private var vaccinationDate = Date()
    @State private var hasNextPlan = false
    @State private var nextDueDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("疫苗信息") {
                    TextField("疫苗名称", text: $vaccineName)
                    DatePicker("接种日期", selection: $vaccinationDate, displayedComponents: .date)
                    Toggle("设置下次计划", isOn: $hasNextPlan)
                    if hasNextPlan {
                        DatePicker("下次日期", selection: $nextDueDate, in: vaccinationDate..., displayedComponents: .date)
                    }
                }
                Section("备注") {
                    TextField("选填", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("记录 \(petName) 的疫苗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(vaccineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let record = VaccinationRecord(
            vaccineName: vaccineName.trimmingCharacters(in: .whitespacesAndNewlines),
            date: vaccinationDate,
            nextDueDate: hasNextPlan ? nextDueDate : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerID: ownerID
        )
        context.insert(record)
        try? context.save()
        dismiss()
    }
}
