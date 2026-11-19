import SwiftUI
import UIKit

/// 语言选择页：点一行立即生效，并且**留在本页**，方便就地对比；
/// 用户自己点返回才离开。
///
/// 之前用的是 `Picker(.navigationLink)`，两只手一起坏事：Picker 会在选中后
/// 自动回退，`MainTabView` 又按语言 `.id(...)` 重建整棵 tab 树把导航栈清空，
/// 于是点一下语言就被弹回设置页。
struct LanguagePickerView: View {
    /// 本地镜像：选中后必须由 `@State` 触发一次整页重算。
    /// 只改 `Localization` 的话 Observation 只会刷新这一行 cell，
    /// 导航栏标题这种同一页里的其它文案不会跟着变。
    @State private var selection = Localization.shared.setting

    var body: some View {
        content
    }

    private var content: some View {
        List {
            ForEach(AppLanguage.allCases) { language in
                row(for: language)
            }
        }
        .navigationTitle(L("语言"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.language.page")
    }

    private func row(for language: AppLanguage) -> some View {
        let isSelected = selection == language
        return Button {
            guard !isSelected else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                Localization.shared.select(language)
            }
            selection = language
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Text(language.displayName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.language.row.\(language.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
