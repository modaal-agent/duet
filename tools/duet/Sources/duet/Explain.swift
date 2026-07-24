// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// `duet explain [--json]` — renders the last run's failures from the machine
/// reports (parity/.runs/): fixture, step label, first-divergence JSON path, both
/// canonical fragments, scenario source:line, and the materialize next-step. No test
/// logs are parsed — the runners already wrote structured truth.
enum Explain {
  static func run(repo: Repo, options: Options) -> Int32 {
    let reports = Lanes.readReports(repo)
    if reports.isEmpty {
      if options.json {
        Lanes.emitJSON(["status": "no-reports"])
      } else {
        print("duet explain: no run reports under parity/.runs — run `duet verify` first")
      }
      return 1
    }
    let failed = Lanes.failedReports(reports)
    if options.json {
      Lanes.emitJSON([
        "status": failed.isEmpty ? "passed" : "failed",
        "failed": failed,
        "total": reports.count,
      ])
      return failed.isEmpty ? 0 : 1
    }
    if failed.isEmpty {
      let platforms = Set(reports.compactMap { $0["platform"] as? String })
        .sorted().joined(separator: ", ")
      print(
        "duet explain: all \(reports.count) fixture report(s) passed "
          + "(\(platforms)) — nothing to explain")
      return 0
    }
    for report in failed {
      for failure in report["failures"] as? [[String: Any]] ?? [] {
        print(Lanes.renderedText(failure: failure, of: report))
      }
    }
    return 1
  }
}
