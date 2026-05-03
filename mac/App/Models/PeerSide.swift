import Foundation

enum PeerSide: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Windows слева"
        case .right: "Windows справа"
        }
    }

    var direction: EdgeDirection {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}
