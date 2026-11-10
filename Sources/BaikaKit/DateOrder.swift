import Foundation

// The iPhoneOS 27.2 SDK declares Foundation's `Date.<=` and `Date.>=` as
// `@backDeployed(before: iOS 27.2)`. The thunk compiled into the app calls the system's copy once
// the OS says 27.2; the 27.2 betas say so without having it, so the weak import is null and the
// first date comparison jumps to address 0 (EXC_BAD_ACCESS, pc = 0 at launch). The simulator's
// older runtime takes the fallback path, so no simulator run can see it.
// See Fabrique-Futur/wine-cave#148 for the original crash.
//
// These two operators shadow Foundation's inside this module, so a date comparison here is a plain
// `TimeInterval` comparison compiled into the app. A module's own declaration wins over an imported
// one; a public copy does not (importing modules see it as ambiguous), so every module that may
// compare dates keeps this same internal file: BaikaKit, BaikaAccounts and the app (App/).
// `~/ops/bin/testflight weak-imports` fails a device build that still weak-imports Foundation's copy.
enum DateOrder {
    static func atOrBefore(_ lhs: Date, _ rhs: Date) -> Bool {
        lhs.timeIntervalSinceReferenceDate <= rhs.timeIntervalSinceReferenceDate
    }

    static func atOrAfter(_ lhs: Date, _ rhs: Date) -> Bool {
        lhs.timeIntervalSinceReferenceDate >= rhs.timeIntervalSinceReferenceDate
    }
}

extension Date {
    static func <= (lhs: Date, rhs: Date) -> Bool { DateOrder.atOrBefore(lhs, rhs) }
    static func >= (lhs: Date, rhs: Date) -> Bool { DateOrder.atOrAfter(lhs, rhs) }
}
