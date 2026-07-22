// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The regeneration switch shared by every fixture writer (ScenarioRunner record mode,
/// RouteSpineTests' golden). The dialect-1 scripted-array recorder that used to live
/// here is gone — every suite is scenario-authored now (FT2), and fixtures are written
/// exclusively by scenario record modes (R10).
public enum FixtureRecorder {
  /// True when the caller should regenerate committed fixtures/goldens
  /// (`REGEN_FIXTURES=1 swift test`, or `verify record`).
  public static var regenerationRequested: Bool {
    ProcessInfo.processInfo.environment["REGEN_FIXTURES"] == "1"
  }
}
