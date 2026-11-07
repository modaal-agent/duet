---
type: llm
---
The answer must say not to keep `@unchecked Sendable`: the stamp removes the compiler's isolation
checking for the worker, and `doctor` reports it with no waiver. The fix it gives must make the
worker an `actor` or a `@MainActor` class (dropping the lock), or a class whose stored state is
`Sendable`, so that `Working`'s `Sendable` conformance is checked.

An answer fails this criterion if it keeps `@unchecked Sendable`, suggests excluding the file
or the check, or moves the class into a test directory to hide it.
