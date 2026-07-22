// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The first point where two JSON trees disagree, as a JSON path plus the canonical
/// fragment on each side (`nil` = the side has nothing at that path). Powers the
/// dialect-2 failure contract: a fixture divergence names the exact leaf, not the
/// whole document. Kotlin mirror: kernel-testsupport FixtureDiff.kt.
public struct FixtureDivergence: Equatable {
  /// Dotted/bracketed path relative to the compared root, e.g. `selected[1].displayName`.
  /// Empty string means the roots themselves differ in type.
  public let path: String
  public let expected: String?
  public let actual: String?

  public init(path: String, expected: String?, actual: String?) {
    self.path = path
    self.expected = expected
    self.actual = actual
  }
}

public enum FixtureDiff {
  /// Walks `expected` and `actual` (parsed `JSONSerialization` trees) in canonical key
  /// order and returns the first divergence, or nil when the trees canonicalize
  /// identically. Object keys are visited in the canonical sort so "first" is
  /// deterministic and matches the byte-compare order.
  public static func firstDivergence(
    expected: Any, actual: Any, path: String = ""
  ) throws -> FixtureDivergence? {
    switch (expected, actual) {
    case let (expectedDict as [String: Any], actualDict as [String: Any]):
      let keys = Set(expectedDict.keys).union(actualDict.keys)
        .sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })
      for key in keys {
        let childPath = path.isEmpty ? key : "\(path).\(key)"
        switch (expectedDict[key], actualDict[key]) {
        case (nil, nil):
          continue
        case let (expectedChild?, nil):
          return FixtureDivergence(
            path: childPath, expected: try fragment(expectedChild), actual: nil)
        case let (nil, actualChild?):
          return FixtureDivergence(
            path: childPath, expected: nil, actual: try fragment(actualChild))
        case let (expectedChild?, actualChild?):
          if let divergence = try firstDivergence(
            expected: expectedChild, actual: actualChild, path: childPath)
          {
            return divergence
          }
        }
      }
      return nil
    case let (expectedArray as [Any], actualArray as [Any]):
      for index in 0..<max(expectedArray.count, actualArray.count) {
        let childPath = "\(path)[\(index)]"
        guard index < expectedArray.count else {
          return FixtureDivergence(
            path: childPath, expected: nil, actual: try fragment(actualArray[index]))
        }
        guard index < actualArray.count else {
          return FixtureDivergence(
            path: childPath, expected: try fragment(expectedArray[index]), actual: nil)
        }
        if let divergence = try firstDivergence(
          expected: expectedArray[index], actual: actualArray[index], path: childPath)
        {
          return divergence
        }
      }
      return nil
    default:
      let expectedFragment = try fragment(expected)
      let actualFragment = try fragment(actual)
      if expectedFragment == actualFragment {
        return nil
      }
      return FixtureDivergence(path: path, expected: expectedFragment, actual: actualFragment)
    }
  }

  private static func fragment(_ value: Any) throws -> String {
    try CanonicalJSON.canonicalString(fromJSONObject: value)
  }
}
