import SwiftUI

struct Agent: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String

    var swiftUIColor: Color {
        switch color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        default: return .accentColor
        }
    }
}

extension Agent {
    static let all: [Agent] = [
        Agent(
            id: "main",
            name: "Hopper",
            description: "Main assistant — general tasks, coordination",
            icon: "brain.head.profile",
            color: "blue"
        ),
        Agent(
            id: "henry",
            name: "Henry",
            description: "MPUSD budget, finance & K-12 operations",
            icon: "chart.bar.doc.horizontal",
            color: "green"
        ),
        Agent(
            id: "mrdag",
            name: "Mr. DAG",
            description: "Bond work, contracts & construction",
            icon: "building.2",
            color: "orange"
        ),
        Agent(
            id: "scout",
            name: "Scout",
            description: "Fast search & research",
            icon: "magnifyingglass",
            color: "purple"
        ),
    ]

    static let `default` = all[0]
}
