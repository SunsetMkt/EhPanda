//
//  WatchedStore.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/09.
//

import ComposableArchitecture

struct WatchedState: Equatable {
    enum Route: Equatable {
        case filters
        case quickSearch
        case detail(String)
    }
    struct CancelID: Hashable {
        let id = String(describing: WatchedState.self)
    }

    init() {
        _detailState = .init(.init())
    }

    @BindingState var route: Route?
    @BindingState var keyword = ""

    var galleries = [Gallery]()
    var pageNumber = PageNumber()
    var loadingState: LoadingState = .idle
    var footerLoadingState: LoadingState = .idle

    var filtersState = FiltersReducer.State()
    var quickSearchState = QuickSearchReducer.State()
    @Heap var detailState: DetailState!

    mutating func insertGalleries(_ galleries: [Gallery]) {
        galleries.forEach { gallery in
            if !self.galleries.contains(gallery) {
                self.galleries.append(gallery)
            }
        }
    }
}

enum WatchedAction: BindableAction {
    case binding(BindingAction<WatchedState>)
    case setNavigation(WatchedState.Route?)
    case clearSubStates
    case onNotLoginViewButtonTapped

    case teardown
    case fetchGalleries(String? = nil)
    case fetchGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)
    case fetchMoreGalleries
    case fetchMoreGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)

    case filters(FiltersReducer.Action)
    case detail(DetailAction)
    case quickSearch(QuickSearchReducer.Action)
}

struct WatchedEnvironment {
    let urlClient: URLClient
    let fileClient: FileClient
    let imageClient: ImageClient
    let deviceClient: DeviceClient
    let hapticsClient: HapticsClient
    let cookieClient: CookieClient
    let databaseClient: DatabaseClient
    let clipboardClient: ClipboardClient
    let appDelegateClient: AppDelegateClient
    let uiApplicationClient: UIApplicationClient
}

let watchedReducer = Reducer<WatchedState, WatchedAction, WatchedEnvironment>.combine(
    .init { state, action, environment in
        switch action {
        case .binding(\.$route):
            return state.route == nil ? .init(value: .clearSubStates) : .none

        case .binding:
            return .none

        case .setNavigation(let route):
            state.route = route
            return route == nil ? .init(value: .clearSubStates) : .none

        case .clearSubStates:
            state.detailState = .init()
            state.filtersState = .init()
            state.quickSearchState = .init()
            return .merge(
                .init(value: .detail(.teardown)),
                .init(value: .quickSearch(.teardown))
            )

        case .onNotLoginViewButtonTapped:
            return .none

        case .teardown:
            return .cancel(id: WatchedState.CancelID())

        case .fetchGalleries(let keyword):
            guard state.loadingState != .loading else { return .none }
            if let keyword = keyword {
                state.keyword = keyword
            }
            state.loadingState = .loading
            state.pageNumber.resetPages()
            let filter = environment.databaseClient.fetchFilterSynchronously(range: .watched)
            return WatchedGalleriesRequest(filter: filter, keyword: state.keyword)
                .effect.map(WatchedAction.fetchGalleriesDone).cancellable(id: WatchedState.CancelID())

        case .fetchGalleriesDone(let result):
            state.loadingState = .idle
            switch result {
            case .success(let (pageNumber, galleries)):
                guard !galleries.isEmpty else {
                    state.loadingState = .failed(.notFound)
                    guard pageNumber.hasNextPage() else { return .none }
                    return .init(value: .fetchMoreGalleries)
                }
                state.pageNumber = pageNumber
                state.galleries = galleries
                return environment.databaseClient.cacheGalleries(galleries).fireAndForget()
            case .failure(let error):
                state.loadingState = .failed(error)
            }
            return .none

        case .fetchMoreGalleries:
            let pageNumber = state.pageNumber
            guard pageNumber.hasNextPage(),
                  state.footerLoadingState != .loading,
                  let lastID = state.galleries.last?.id
            else { return .none }
            state.footerLoadingState = .loading
            let filter = environment.databaseClient.fetchFilterSynchronously(range: .watched)
            return MoreWatchedGalleriesRequest(filter: filter, lastID: lastID, keyword: state.keyword).effect
                .map(WatchedAction.fetchMoreGalleriesDone)
                .cancellable(id: WatchedState.CancelID())

        case .fetchMoreGalleriesDone(let result):
            state.footerLoadingState = .idle
            switch result {
            case .success(let (pageNumber, galleries)):
                state.pageNumber = pageNumber
                state.insertGalleries(galleries)

                var effects: [EffectTask<WatchedAction>] = [
                    environment.databaseClient.cacheGalleries(galleries).fireAndForget()
                ]
                if galleries.isEmpty, pageNumber.hasNextPage() {
                    effects.append(.init(value: .fetchMoreGalleries))
                } else if !galleries.isEmpty {
                    state.loadingState = .idle
                }
                return .merge(effects)

            case .failure(let error):
                state.footerLoadingState = .failed(error)
            }
            return .none

        case .quickSearch:
            return .none

        case .filters:
            return .none

        case .detail:
            return .none
        }
    }
    .haptics(
        unwrapping: \.route,
        case: /WatchedState.Route.quickSearch,
        hapticsClient: \.hapticsClient
    )
    .haptics(
        unwrapping: \.route,
        case: /WatchedState.Route.filters,
        hapticsClient: \.hapticsClient
    )
    .binding(),
//    filtersReducer.pullback(
//        state: \.filtersState,
//        action: /WatchedAction.filters,
//        environment: {
//            .init(
//                databaseClient: $0.databaseClient
//            )
//        }
//    ),
//    quickSearchReducer.pullback(
//        state: \.quickSearchState,
//        action: /WatchedAction.quickSearch,
//        environment: {
//            .init(
//                databaseClient: $0.databaseClient
//            )
//        }
//    ),
    detailReducer.pullback(
        state: \.detailState,
        action: /WatchedAction.detail,
        environment: {
            .init(
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                hapticsClient: $0.hapticsClient,
                cookieClient: $0.cookieClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    )
)
