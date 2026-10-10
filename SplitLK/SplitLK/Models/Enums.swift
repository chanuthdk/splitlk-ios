import Foundation

enum SplitMode: String, CaseIterable, Identifiable {
    case equally, byItem, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .equally: return "Equally"
        case .byItem:  return "By Item"
        case .custom:  return "Custom"
        }
    }
}

enum SpendingCategory: String, CaseIterable, Identifiable {
    case food, drinks, transport, groceries, accommodation, other

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .food:          return "fork.knife"
        case .drinks:        return "cup.and.saucer.fill"
        case .transport:     return "car.fill"
        case .groceries:     return "cart.fill"
        case .accommodation: return "bed.double.fill"
        case .other:         return "tag.fill"
        }
    }
}
