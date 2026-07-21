import SwiftUI
import PhotosUI

/// 认识新朋友（PRD §5.2，Panora Batch 4）：自建 sheet 头 + 200pt 照片投放区
/// + 玻璃卡表单（名字/性别公母药丸/年龄/认识日期）。保存后后台跑 Tripo，可离开页面。
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                sheetHeader
                ScrollView {
                    VStack(spacing: 18) {
                        photoDropzone
                        Text("单张照片即可 · 侧面清晰效果最好")
                            .font(.system(size: 12))
                            .foregroundStyle(Panora.textMuted)
                            .frame(maxWidth: .infinity)
                        formCard
                        Text("保存后在后台生成 3D，可以离开这个页面。")
                            .font(.system(size: 12))
                            .foregroundStyle(Panora.textMuted)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .photoSourcePicker(isPresented: $showPhotoOptions) { avatarData = $0 }
    }

    // MARK: - 头

    private var sheetHeader: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Panora.textSecondary)
            Spacer()
            Text("认识新朋友")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Panora.textPrimary)
            Spacer()
            Button("保存") { save() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(name.isEmpty ? Panora.textFaint : Panora.lime)
                .disabled(name.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - 照片投放区

    private var photoDropzone: some View {
        Button { showPhotoOptions = true } label: {
            ZStack {
                if let avatarData, let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Panora.darkCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                                )
                                .foregroundStyle(Panora.cardBorder)
                        )
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Panora.textMuted)
                        Text("拍照 / 选图")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Panora.textSecondary)
                        Text("用于生成 3D")
                            .font(.system(size: 11))
                            .foregroundStyle(Panora.textMuted)
                    }
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 表单卡

    private var formCard: some View {
        VStack(spacing: 0) {
            formRow(label: "名字") {
                TextField("", text: $name, prompt: Text("必填").foregroundColor(Panora.textFaint))
                    .font(.system(size: 15))
                    .foregroundStyle(Panora.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            divider
            formRow(label: "性别") {
                HStack(spacing: 6) {
                    genderPill("公")
                    genderPill("母")
                }
            }
            divider
            formRow(label: "年龄") {
                TextField("", text: $ageText,
                          prompt: Text("如「约 3 岁」").foregroundColor(Panora.textFaint))
                    .font(.system(size: 15))
                    .foregroundStyle(Panora.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            divider
            formRow(label: "认识日期") {
                // DatePicker.compact 会显示成一个小胶囊按钮，跟 spec 里那种「点了展开」的样式一致。
                DatePicker("", selection: $metDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
            }
        }
        .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
        )
    }

    private func formRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Panora.textSecondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
    }

    private func genderPill(_ value: String) -> some View {
        let selected = gender == value
        return Button {
            gender = selected ? "" : value   // 再点一下反选
        } label: {
            Text(value)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Panora.lime : Panora.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(
                    selected ? Panora.lime.opacity(0.20) : Color.white.opacity(0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 保存

    private func save() {
        let friend = DogFriend(
            name: name, gender: gender, ageText: ageText,
            metDate: metDate, avatarData: avatarData
        )
        context.insert(friend)
        dismiss()

        guard let avatarData else { return }
        Task {
            await generator.generate(photoData: avatarData, into: friend)
        }
    }
}
