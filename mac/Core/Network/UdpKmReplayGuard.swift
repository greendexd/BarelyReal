import Foundation

public final class UdpKmReplayGuard {
    public enum Lane: Hashable {
        case flow
        case input
    }

    private let windowSize: UInt32
    private var lanes: [Lane: LaneState] = [:]

    public init(windowSize: UInt32 = 1_024) {
        self.windowSize = windowSize
    }

    public func accepts(_ frame: KmFrame) -> Bool {
        let lane = Self.lane(for: frame.type)
        var state = lanes[lane] ?? LaneState(windowSize: windowSize)
        let accepted = state.accepts(frame.seq)
        lanes[lane] = state
        return accepted
    }

    public func reset() {
        lanes.removeAll()
    }

    private static func lane(for type: KmType) -> Lane {
        switch type {
        case .heartbeat, .clockSync:
            return .flow
        case .mouseMoveRel, .mouseMoveAbs, .mouseButton, .mouseScroll, .keyDown, .keyUp, .modifiersChanged:
            return .input
        }
    }
}

private struct LaneState {
    let windowSize: UInt32
    var maxSeen: UInt32?
    var seen: Set<UInt32> = []

    mutating func accepts(_ seq: UInt32) -> Bool {
        guard let currentMax = maxSeen else {
            maxSeen = seq
            seen = [seq]
            return true
        }

        if Self.isNewer(seq, than: currentMax) {
            maxSeen = seq
            seen.insert(seq)
            prune()
            return true
        }

        guard let behind = Self.distanceBehind(seq, max: currentMax),
              behind <= windowSize,
              !seen.contains(seq)
        else {
            return false
        }

        seen.insert(seq)
        prune()
        return true
    }

    private mutating func prune() {
        guard let maxSeen else { return }
        seen = Set(seen.filter { seq in
            guard let behind = Self.distanceBehind(seq, max: maxSeen) else {
                return false
            }
            return behind <= windowSize
        })
    }

    private static func isNewer(_ seq: UInt32, than maxSeen: UInt32) -> Bool {
        let delta = seq &- maxSeen
        return delta != 0 && delta < 0x8000_0000
    }

    private static func distanceBehind(_ seq: UInt32, max maxSeen: UInt32) -> UInt32? {
        if seq == maxSeen { return 0 }
        let delta = maxSeen &- seq
        return delta < 0x8000_0000 ? delta : nil
    }
}
