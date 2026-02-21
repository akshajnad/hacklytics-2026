//
//  RingBuffer.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation

struct RingBuffer<T> {
    private var buf: [T?]
    private var head: Int = 0
    private var count: Int = 0

    init(capacity: Int) {
        buf = Array(repeating: nil, count: max(1, capacity))
    }

    mutating func push(_ x: T) {
        buf[head] = x
        head = (head + 1) % buf.count
        count = min(count + 1, buf.count)
    }

    func allItems() -> [T] {
        var out: [T] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let idx = (head - 1 - i + buf.count) % buf.count
            if let v = buf[idx] { out.append(v) }
        }
        return out.reversed()
    }
}

// Helper for SpeakerSample
extension RingBuffer where T == SpeakerSample {
    func closest(to time: TimeInterval) -> SpeakerSample? {
        let items = allItems()
        guard !items.isEmpty else { return nil }

        var best: SpeakerSample? = nil
        var bestD = Double.greatestFiniteMagnitude

        for s in items {
            let d = abs(s.time - time)
            if d < bestD {
                bestD = d
                best = s
            }
        }
        return best
    }
}
