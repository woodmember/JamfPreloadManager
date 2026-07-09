enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case find
    case add
    case modify
    case bulk
    case delete

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:
            "Overview"
        case .find:
            "Find Entry"
        case .add:
            "Add Entry"
        case .modify:
            "Modify Entry"
        case .bulk:
            "Bulk Update"
        case .delete:
            "Delete Entry"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            "Connection health and quick actions"
        case .find:
            "Search preload records by serial"
        case .add:
            "Create new preload records"
        case .modify:
            "Load and update existing records"
        case .bulk:
            "CSV upload, overwrite, and delete tools"
        case .delete:
            "Admin-only permanent removal"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "rectangle.3.group.bubble.left"
        case .find:
            "magnifyingglass"
        case .add:
            "plus.circle"
        case .modify:
            "square.and.pencil"
        case .bulk:
            "square.3.layers.3d.down.right"
        case .delete:
            "trash"
        }
    }
}
