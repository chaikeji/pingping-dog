import SwiftUI
import PhotosUI

/// 认识新朋友（PRD §5.2）：名字必填 + 性别 / 手填年龄 / 认识日期 + 单张照片。
/// 不再要品种 / 主人。保存后后台跑 Tripo，可离开页面。
struct AddFriendView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var gender = ""
    @State private var ageText = ""
    @State private var metDate = Date.now
    @State private var showPhotoOptions = false
    @State private var avatarData: Data?

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())
    private let genders = ["公", "母"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("狗狗名字（必填）", text: $name)
                    Picker("性别", selection: $gender) {
                        Text("未填").tag("")
                        ForEach(genders, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("年龄（如「约 3 岁」）", text: $ageText)
                    DatePicker("认识日期", selection: $metDate, displayedComponents: .date)
                }
                Section {
                    Button("选择照片（用于生成 3D 模型）") { showPhotoOptions = true }
                    if let avatarData, let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(height: 160)
                    }
                }
            }
            .navigationTitle("认识新朋友")
            .toolbar {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
            .photoSourcePicker(isPresented: $showPhotoOptions) { avatarData = $0 }
        }
    }

    private func save() {
        let friend = DogFriend(name: name, gender: gender, ageText: ageText, metDate: metDate, avatarData: avatarData)
        context.insert(friend)
        dismiss()

        guard let avatarData else { return }
        Task {
            await generator.generate(photoData: avatarData, into: friend)
        }
    }
}
