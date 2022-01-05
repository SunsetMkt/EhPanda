//
//  TabBarView.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/12/29.
//

import SwiftUI
import SFSafeSymbols
import ComposableArchitecture

struct TabBarView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let store: Store<AppState, AppAction>
    @ObservedObject private var viewStore: ViewStore<AppState, AppAction>

    init(store: Store<AppState, AppAction>) {
        self.store = store
        viewStore = ViewStore(store)
    }

    var body: some View {
        ZStack {
            TabView(selection: viewStore.binding(\.tabBarState.$tabBarItemType)) {
                ForEach(TabBarItemType.allCases) { type in
                    Group {
                        switch type {
                        case .favorites:
                            FavoritesView(
                                store: store.scope(state: \.favoritesState, action: AppAction.favorites),
                                user: viewStore.settingState.user, setting: viewStore.settingState.setting,
                                tagTranslator: viewStore.settingState.tagTranslator
                            )
                        case .search:
                            NavigationView {
                                Text(type.rawValue.localized).navigationTitle(type.rawValue.localized)
                            }
                        case .setting:
                            SettingView(
                                store: store.scope(state: \.settingState, action: AppAction.setting),
                                blurRadius: viewStore.appLockState.blurRadius
                            )
                        }
                    }
                    .tabItem(type.label).tag(type)
                }
                .accentColor(viewStore.settingState.setting.accentColor)
            }
            .blur(radius: viewStore.appLockState.blurRadius)
            .allowsHitTesting(!viewStore.appLockState.isAppLocked)
            .animation(.linear(duration: 0.1), value: viewStore.appLockState.blurRadius)
            Image(systemSymbol: .lockFill).font(.system(size: 80))
                .opacity(viewStore.appLockState.isAppLocked ? 1 : 0)
        }
        .onChange(of: scenePhase) { newValue in
            viewStore.send(.onScenePhaseChange(newValue))
        }
    }
}

// MARK: TabType
enum TabBarItemType: String, CaseIterable, Identifiable {
    var id: String { rawValue }

//    case home = "Home"
    case favorites = "Favorites"
    case search = "Search"
    case setting = "Setting"
}

extension TabBarItemType {
    var symbol: SFSymbol {
        switch self {
//        case .home:
//            return .houseCircle
        case .favorites:
            return .heartCircle
        case .search:
            return .magnifyingglassCircle
        case .setting:
            return .gearshapeCircle
        }
    }
    func label() -> Label<Text, Image> {
        Label(rawValue.localized, systemSymbol: symbol)
    }
}
