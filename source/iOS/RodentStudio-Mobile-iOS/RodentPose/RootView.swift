// RootView.swift — tabs (Home · Paradigms · Data), the new-session sheet and the session workspace.

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $app.selectedTab) {
            HomeView()
                .tabItem { Label(L10n.tr("首页"), systemImage: "house") }
                .tag(AppTab.home)
            CatalogView()
                .tabItem { Label(L10n.tr("范式库"), systemImage: "square.grid.2x2") }
                .tag(AppTab.catalog)
            LibraryView()
                .tabItem { Label(L10n.tr("数据"), systemImage: "tray.full") }
                .tag(AppTab.library)
        }
        .sheet(item: $app.newSessionRequest, onDismiss: { app.presentPendingFlow() }) { request in
            NewSessionSheet(initialParadigm: request.paradigm)
        }
        .fullScreenCover(item: $app.activeFlow) { flow in
            SessionFlowView(flow: flow)
        }
        .onChange(of: scenePhase) { _, phase in
            app.scenePhaseChanged(phase)
        }
    }
}
