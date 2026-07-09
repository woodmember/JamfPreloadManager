import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(AppSection.allCases, selection: selectionBinding) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(section.title, systemImage: section.systemImage)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(section)
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                connectionFooter
            }
            .navigationTitle(AppConstants.appName)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            Group {
                if model.isBootstrapping {
                    ProgressView("Loading saved Jamf settings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch model.selectedSection ?? .dashboard {
                    case .dashboard:
                        DashboardView(model: model)
                    case .find:
                        FindEntryView(model: model)
                    case .add:
                        RecordEditorView(model: model, mode: .add)
                    case .modify:
                        RecordEditorView(model: model, mode: .modify)
                    case .bulk:
                        BulkUpdateView(model: model)
                    case .delete:
                        DeleteEntryView(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var selectionBinding: Binding<AppSection?> {
        Binding(
            get: { model.selectedSection },
            set: { model.selectedSection = $0 }
        )
    }

    private var connectionFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Label(model.connectionState.title, systemImage: model.connectionState.systemImage)
                .font(.headline)
            Text(model.connectionState.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(minHeight: 102, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
