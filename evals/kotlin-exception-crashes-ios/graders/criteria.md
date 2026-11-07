---
type: llm
---
The answer must say that a Kotlin exception crossing into Swift through a function without
`@Throws` terminates the process, add `@Throws(...)` naming `SerializationException` (or a
superclass such as `IllegalArgumentException` or `Exception`) to `restore`, and call it from
Swift with `try` inside `do`/`catch`. It must say the framework is assembled again (or rebuilt)
before the Swift side sees the change.

An answer fails this criterion if it only wraps the Swift call in `do`/`catch` without the
Kotlin annotation, or catches the exception in Kotlin and returns a default state silently.
