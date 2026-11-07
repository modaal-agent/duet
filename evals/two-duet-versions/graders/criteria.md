---
type: llm
---
The answer must say that duet-services pins `duet` exactly, so the tree's `duet` pin has to be
the version that duet-services release pins (`0.8.0` here); move `duet` to it in the same change,
as an `exact:` pin, and move the Kotlin catalog's `duet` entry to the same version.

An answer fails this criterion if it loosens a pin to `from:` or a range, or reverts
duet-services without saying that the two pins move together.
