import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [DogProfile]
    @State private var isEditing = false

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        avatarView
                        VStack(alignment: .leading) {
                            Text(profile.name).font(.title2.bold())
                            Text(profile.breed.isEmpty ? "未填写品种" : profile.breed)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let birthday = profile.birthday {
                    Section("生日") {
                        Text(birthday.formatted(date: .long, time: .omitted))
                    }
                }
            }
            .navigationTitle("平平档案")
            .toolbar {
                Button("编辑") { isEditing = true }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(profile: profile)
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let data = profile.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(width: 64, height: 64).clipShape(Circle())
        } else {
            Image(systemName: "pawprint.circle.fill")
                .resizable().frame(width: 64, height: 64).foregroundStyle(.orange)
        }
    }
}

private struct ProfileEditView: View {
    @Bindable var profile: DogProfile
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名字", text: $profile.name)
                TextField("品种", text: $profile.breed)
                DatePicker(
                    "生日",
                    selection: Binding(get: { profile.birthday ?? .now }, set: { profile.birthday = $0 }),
                    displayedComponents: .date
                )
                PhotosPicker("选择头像", selection: $pickerItem, matching: .images)
            }
            .navigationTitle("编辑档案")
            .toolbar {
                Button("完成") { dismiss() }
            }
            .task(id: pickerItem) {
                if let pickerItem, let data = try? await pickerItem.loadTransferable(type: Data.self) {
                    profile.avatarData = data
                }
            }
        }
    }
}
