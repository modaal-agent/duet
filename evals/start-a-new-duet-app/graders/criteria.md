---
type: llm
---
The answer must start the project from the duet-tutorials repository's `tutorial1-start` tree
(Kotlin Multiplatform flavor) or `tutorial1-swift-start` (Swift flavor), or by following the
tutorial series by hand, and must then run the tree's checks (`tools/duet verify` or
`tools/duet lint`).

An answer fails this criterion if it tells the user to run a command that creates a project
through the `duet` CLI (`duet init`, `duet new`, `duet scaffold`, `duet create`), or to
generate the project with a Kotlin Multiplatform wizard or template that is not a Duet tree.
Stating that no such `duet` verb exists is correct and does not fail the criterion.
