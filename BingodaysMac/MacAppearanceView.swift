import SwiftUI

struct MacAppearanceView: View {
    @AppStorage(AppSettings.themeKey) private var themeRaw = AppTheme.concise.rawValue
    @AppStorage(AppSettings.homeBackgroundKey) private var skinRaw = HomeBackgroundOption.none.rawValue
    @State private var showMobile = false
    private let names = ["concise": "奶油", "violet": "紫藤", "sky": "晴空", "indigo": "靛蓝", "lime": "森林", "coral": "珊瑚", "amber": "琥珀", "mint": "薄荷"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("让棋盘变成喜欢的样子").font(.title3.bold())
                Text("主题配色").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(AppTheme.selectableCases) { theme in
                        Button { themeRaw = theme.rawValue } label: {
                            VStack(spacing: 6) {
                                Circle().fill(theme.color).frame(width: 40, height: 40)
                                    .overlay { if themeRaw == theme.rawValue { Image(systemName: "checkmark").foregroundStyle(.white).font(.headline) } }
                                Text(names[theme.rawValue] ?? theme.rawValue).font(.caption)
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(names[theme.rawValue] ?? theme.rawValue)
                            .accessibilityAddTraits(themeRaw == theme.rawValue ? [.isSelected] : [])
                    }
                }
                Divider()
                Text("背景皮肤").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(HomeBackgroundOption.allCases) { skin in
                        Button {
                            if skin.isPremiumOnly { showMobile = true } else { skinRaw = skin.rawValue }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                RoundedRectangle(cornerRadius: 12).fill(Color(hex: "FAF7F2"))
                                if let image = skin.imageName {
                                    Image(image).resizable().scaledToFill().frame(height: 94).clipped()
                                } else { Text("简洁").frame(maxWidth: .infinity, maxHeight: .infinity) }
                                if skinRaw == skin.rawValue { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .brown).padding(7) }
                                else if skin.isPremiumOnly { Image(systemName: "lock.fill").padding(6).background(.regularMaterial, in: Circle()).padding(5) }
                            }
                            .frame(height: 94).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(skinRaw == skin.rawValue ? Color.accentColor : .clear, lineWidth: 3) }
                        }.buttonStyle(.plain)
                            .help(skin.isPremiumOnly ? "前往移动端体验会员皮肤" : (skin == .none ? "简洁背景" : "应用皮肤 \(skin.rawValue)"))
                            .accessibilityLabel(skin == .none ? "简洁背景" : "皮肤 \(skin.rawValue)")
                    }
                }
                Text("会员皮肤请前往移动端体验。").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .sheet(isPresented: $showMobile) { MacMobileFeaturesView() }
    }
}
