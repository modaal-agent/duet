// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// `duet materialize <fixture>#<step> --platform swift|kotlin` — converts a fixture
/// step into a compiling, standalone, *failing-where-the-fixture-failed* unit test on
/// the chosen platform: prior state + action embedded as JSON, decoded through the
/// platform's canonical decoder, one reducer call, canonical byte assertions. The
/// generated test is a debugging scaffold (breakpoints, IDE) — delete after use
/// (`duet materialize --clean`).
enum Materialize {
  static func run(repo: Repo, options: Options) throws -> Int32 {
    let manifest = try Manifest.load(repo: repo)
    if options.clean {
      let removed = clean(repo: repo, manifest: manifest)
      print("duet materialize: removed \(removed) generated test file(s)")
      return 0
    }
    guard let target = options.target else {
      print("usage: duet materialize <fixture>#<step> --platform swift|kotlin (or --clean)")
      return 2
    }
    let pieces = target.split(separator: "#")
    guard pieces.count == 2, let step = Int(pieces[1]) else {
      print("duet materialize: target must be <fixture>#<step>, got '\(target)'")
      return 2
    }
    let fixture = String(pieces[0])
    guard let platform = options.platform, ["swift", "kotlin"].contains(platform) else {
      print("duet materialize: --platform swift|kotlin is required")
      return 2
    }

    let fixtureURL = repo.fixturesDir.appendingPathComponent("\(fixture).fixture.json")
    guard let data = try? Data(contentsOf: fixtureURL),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let steps = root["steps"] as? [[String: Any]]
    else {
      print("duet materialize: cannot read \(fixtureURL.path)")
      return 1
    }
    guard step >= 0, step < steps.count else {
      print("duet materialize: step \(step) out of range (fixture has \(steps.count) steps)")
      return 1
    }
    let stepObject = steps[step]
    guard let action = stepObject["action"],
      let expectedEffects = stepObject["expectedEffects"]
    else {
      print("duet materialize: step \(step) is malformed")
      return 1
    }
    let label = stepObject["label"] as? String

    let featureName: String
    let prior: Any
    // The node's own earlier actions (chain fixtures interleave nodes and record no
    // state — the standalone repro replays this node from its seed). Empty for
    // feature fixtures, whose prior step carries the full state.
    let priorActions: [Any]
    // Chains pin effects only; nil suppresses the state assertion.
    let expectedState: Any?
    if root["chain"] is String {
      guard let node = stepObject["node"] as? String else {
        print("duet materialize: chain step \(step) has no node")
        return 1
      }
      guard let initialStates = root["initialStates"] as? [String: Any],
        let seed = initialStates[node]
      else {
        print(
          "duet materialize: chain fixture has no initialStates['\(node)'] — "
            + "regenerate (dialect 2): duet record")
        return 1
      }
      featureName = node
      prior = seed
      priorActions = steps[..<step]
        .filter { ($0["node"] as? String) == node }
        .compactMap { $0["action"] }
      expectedState = nil
    } else {
      guard let owner = root["feature"] as? String else {
        print("duet materialize: fixture '\(fixture)' names no feature")
        return 1
      }
      guard let rawInitialState = root["initialState"] else {
        print("duet materialize: fixture '\(fixture)' has no initialState")
        return 1
      }
      featureName = owner
      prior = step == 0 ? rawInitialState : steps[step - 1]["expectedState"]!
      priorActions = []
      expectedState = stepObject["expectedState"]
    }
    guard let feature = manifest.feature(named: featureName) else {
      print(
        "duet materialize: '\(featureName)' is not a manifest feature "
          + "(chain node keys must be feature names)")
      return 1
    }

    let file: URL
    let runHint: String
    if platform == "swift" {
      guard let module = feature.swiftModule, let testTarget = feature.swiftTestTarget else {
        print("duet materialize: cannot derive Swift module for '\(featureName)'")
        return 1
      }
      let className = "Materialized_\(sanitize(fixture))_step\(step)_Tests"
      file = manifest.swiftPackageDir
        .appendingPathComponent("Tests/\(testTarget)/\(className).swift")
      try swiftTest(
        className: className, module: module, feature: feature, fixture: fixture,
        step: step, label: label, prior: prior, priorActions: priorActions,
        action: action, expectedState: expectedState, expectedEffects: expectedEffects
      ).write(to: file, atomically: true, encoding: .utf8)
      runHint =
        "cd \(manifest.swiftPackageDir.path) && swift test --filter \(className)"
    } else {
      guard let task = feature.gradleTestTask, let modulePath = feature.kotlinModulePath,
        let package = feature.kotlinPackage
      else {
        print("duet materialize: cannot derive Gradle module for '\(featureName)'")
        return 1
      }
      let className = "Materialized_\(sanitize(fixture))_step\(step)_Test"
      let packagePath = package.replacingOccurrences(of: ".", with: "/")
      file = manifest.androidDir
        .appendingPathComponent("\(modulePath)/src/test/kotlin/\(packagePath)/\(className).kt")
      try kotlinTest(
        className: className, package: package, feature: feature, fixture: fixture,
        step: step, label: label, prior: prior, priorActions: priorActions,
        action: action, expectedState: expectedState, expectedEffects: expectedEffects
      ).write(to: file, atomically: true, encoding: .utf8)
      runHint =
        "cd \(manifest.androidDir.path) && ./gradlew \(task) --tests '*\(className)*'"
    }
    if options.json {
      Lanes.emitJSON(["status": "written", "file": file.path, "run": runHint])
    } else {
      print("duet materialize: wrote \(file.path)")
      print("run it: \(runHint)")
      print("clean up afterwards: duet materialize --clean")
    }
    return 0
  }

  private static func sanitize(_ name: String) -> String {
    name.replacingOccurrences(of: "-", with: "_")
  }

  private static func compactJSON(_ tree: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: tree, options: [.sortedKeys, .fragmentsAllowed])
    return String(data: data, encoding: .utf8) ?? "null"
  }

  private static func swiftTest(
    className: String, module: String, feature: Feature, fixture: String, step: Int,
    label: String?, prior: Any, priorActions: [Any], action: Any, expectedState: Any?,
    expectedEffects: Any
  ) throws -> String {
    let header = label.map { " — '\($0)'" } ?? ""
    // Chain steps: replay the node's own earlier actions from its seed (chains record
    // no state); feature steps embed the prior step's full state and replay nothing.
    let stateAssert = try expectedState.map { expected in
      """

          let expectedStateJSON = ###"\(try compactJSON(expected))"###
          XCTAssertEqual(
            try CanonicalJSON.canonicalString(of: state), try canonical(expectedStateJSON),
            "fixture '\(fixture)' step \(step): state diverged")
      """
    } ?? ""
    return """
      // Generated by `duet materialize \(fixture)#\(step) --platform swift`.
      // A standalone re-run of one fixture step\(header): decode prior state, apply the
      // action, canonical-compare. Debug here (breakpoints in \(feature.reducerName)),
      // then DELETE this file (`duet materialize --clean`).

      import Foundation
      import DuetTesting
      import XCTest
      import \(module)

      final class \(className): XCTestCase {
        func testStep\(step)() throws {
          let priorStateJSON = ###"\(try compactJSON(prior))"###
          let priorActionsJSON = ###"\(try compactJSON(priorActions))"###
          let actionJSON = ###"\(try compactJSON(action))"###
          let expectedEffectsJSON = ###"\(try compactJSON(expectedEffects))"###

          func canonical(_ json: String) throws -> String {
            try CanonicalJSON.canonicalString(
              fromJSONObject: JSONSerialization.jsonObject(
                with: Data(json.utf8), options: [.fragmentsAllowed]))
          }
          let decoder = FixtureRunner.canonicalDecoder()
          var state = try decoder.decode(
            \(feature.stateType).self, from: Data(priorStateJSON.utf8))
          for rawAction in try JSONSerialization.jsonObject(
            with: Data(priorActionsJSON.utf8)) as! [Any]
          {
            let prior = try decoder.decode(
              \(feature.actionType).self,
              from: JSONSerialization.data(withJSONObject: rawAction, options: [.fragmentsAllowed]))
            _ = \(feature.reducerName)(state: &state, action: prior)
          }
          let action = try decoder.decode(
            \(feature.actionType).self, from: Data(actionJSON.utf8))

          let effects = \(feature.reducerName)(state: &state, action: action)
      \(stateAssert)
          XCTAssertEqual(
            try CanonicalJSON.canonicalString(of: effects), try canonical(expectedEffectsJSON),
            "fixture '\(fixture)' step \(step): effects diverged")
        }
      }
      """
  }

  private static func kotlinTest(
    className: String, package: String, feature: Feature, fixture: String, step: Int,
    label: String?, prior: Any, priorActions: [Any], action: Any, expectedState: Any?,
    expectedEffects: Any
  ) throws -> String {
    // Kotlin raw strings interpolate `$` — escape it; JSON cannot contain `"""`.
    func raw(_ tree: Any) throws -> String {
      "\"\"\"" + (try compactJSON(tree)).replacingOccurrences(of: "$", with: "${'$'}")
        + "\"\"\""
    }
    let header = label.map { " — '\($0)'" } ?? ""
    let stateAssert = try expectedState.map { expected in
      """

          val expectedStateJson = \(try raw(expected))
          assertEquals(
            canonical(expectedStateJson),
            CanonicalJson.canonicalString(json.encodeToJsonElement(\(feature.stateType).serializer(), state)),
            "fixture '\(fixture)' step \(step): state diverged")
      """
    } ?? ""
    return """
      // Generated by `duet materialize \(fixture)#\(step) --platform kotlin`.
      // A standalone re-run of one fixture step\(header): decode prior state, apply the
      // action, canonical-compare. Debug here (breakpoints in \(feature.reducerName)),
      // then DELETE this file (`duet materialize --clean`).

      package \(package)

      import dev.modaal.duet.kernel.serialization.CanonicalJson
      import dev.modaal.duet.kernel.serialization.effectToJson
      import dev.modaal.duet.test.FixtureRunner
      import kotlin.test.Test
      import kotlin.test.assertEquals
      import kotlinx.serialization.json.JsonArray
      import kotlinx.serialization.json.jsonArray

      class \(className) {
        @Test
        fun step\(step)() {
          val json = FixtureRunner.json
          val priorStateJson = \(try raw(prior))
          val priorActionsJson = \(try raw(priorActions))
          val actionJson = \(try raw(action))
          val expectedEffectsJson = \(try raw(expectedEffects))

          fun canonical(raw: String): String =
            CanonicalJson.canonicalString(json.parseToJsonElement(raw))
          var state = json.decodeFromString(\(feature.stateType).serializer(), priorStateJson)
          for (rawAction in json.parseToJsonElement(priorActionsJson).jsonArray) {
            val prior = json.decodeFromJsonElement(\(feature.actionType)Serializer, rawAction)
            state = \(feature.reducerName)(state, prior).state
          }
          val action = json.decodeFromString(\(feature.actionType)Serializer, actionJson)

          val reduced = \(feature.reducerName)(state, action)
          state = reduced.state
      \(stateAssert)
          assertEquals(
            canonical(expectedEffectsJson),
            CanonicalJson.canonicalString(
              JsonArray(reduced.effects.map { effectToJson(it, \(feature.payloadType)Serializer, json) })),
            "fixture '\(fixture)' step \(step): effects diverged")
        }
      }
      """
  }

  /// Deletes every generated `Materialized_*` test on both platforms.
  static func clean(repo: Repo, manifest: Manifest) -> Int {
    var removed = 0
    let roots = [
      manifest.swiftPackageDir.appendingPathComponent("Tests"),
      manifest.androidDir,
    ]
    for root in roots {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: nil)
      else { continue }
      for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if name.hasPrefix("Materialized_"), name.hasSuffix(".swift") || name.hasSuffix(".kt"),
          !url.path.contains("/build/")
        {
          if (try? FileManager.default.removeItem(at: url)) != nil {
            removed += 1
          }
        }
      }
    }
    return removed
  }
}
