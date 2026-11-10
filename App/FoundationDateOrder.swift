import Foundation

// Defines Foundation's own `Date.<=` and `Date.>=` symbols inside the app binary.
//
// DateOrder.swift (one internal copy per module) covers Baika's own code. Packages compiled into
// the app that compare dates (FabriqueAccounts and its dependencies) still weak-import the
// system's copy, which iOS 27.2 betas lack: a signed-in launch would jump to address 0 there.
// The static linker binds an undefined symbol to a definition in the image before it looks at a
// dylib, so these two definitions take every such reference, and the binary no longer imports them.
//
// The ABI matches the real operators. Outside Foundation `Date` is resilient, so callers and this
// definition both pass the two dates by address (x0, x1) and no `self` (a struct's metatype is
// thin).
// This file must stay in a module that does not call Foundation's operators itself (the app
// module has App/DateOrder.swift). `~/ops/bin/testflight weak-imports` fails the device build
// if either symbol is still a weak import.
@_silgen_name("$s10Foundation4DateV2leoiySbAC_ACtFZ")
@inline(never)
public func foundationDateAtOrBefore(_ lhs: Date, _ rhs: Date) -> Bool {
    DateOrder.atOrBefore(lhs, rhs)
}

@_silgen_name("$s10Foundation4DateV2geoiySbAC_ACtFZ")
@inline(never)
public func foundationDateAtOrAfter(_ lhs: Date, _ rhs: Date) -> Bool {
    DateOrder.atOrAfter(lhs, rhs)
}
