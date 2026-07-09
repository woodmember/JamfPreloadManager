enum OperationInputMode: String, CaseIterable, Identifiable {
    case single
    case bulkCSV

    var id: Self { self }

    var title: String {
        switch self {
        case .single:
            "Single"
        case .bulkCSV:
            "Bulk CSV"
        }
    }
}
