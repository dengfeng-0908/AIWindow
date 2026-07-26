import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            AIHotView()
                .tabItem {
                    Label("资讯", systemImage: "newspaper")
                }

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "star")
                }

            HistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(.accentColor)
    }
}
