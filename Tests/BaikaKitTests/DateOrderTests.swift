import Foundation
import Testing
@testable import BaikaKit

/// BaikaKit's `Date <=` / `>=` (DateOrder.swift) must answer exactly as Foundation's `compare`.
@Suite("Date order") struct DateOrderTests {
    let early = Date(timeIntervalSinceReferenceDate: 100)
    let late = Date(timeIntervalSinceReferenceDate: 100.5)

    @Test func atOrBefore() {
        #expect(DateOrder.atOrBefore(early, late))
        #expect(DateOrder.atOrBefore(early, early))
        #expect(!DateOrder.atOrBefore(late, early))
    }

    @Test func atOrAfter() {
        #expect(DateOrder.atOrAfter(late, early))
        #expect(DateOrder.atOrAfter(late, late))
        #expect(!DateOrder.atOrAfter(early, late))
    }

    @Test func agreesWithCompare() {
        let dates = (0..<20).map { Date(timeIntervalSinceReferenceDate: Double($0 % 7) * 0.25) }
        for a in dates {
            for b in dates {
                #expect(DateOrder.atOrBefore(a, b) == (a.compare(b) != .orderedDescending))
                #expect(DateOrder.atOrAfter(a, b) == (a.compare(b) != .orderedAscending))
            }
        }
    }
}
