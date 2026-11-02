// Durable recovery journal.
//
// The journal records the windows this WM minimized or parked before the
// mutation. It is written atomically with owner-only permissions. A versioned
// envelope lets a newer helper refuse an unknown format instead of decoding
// it as the wrong shape; a legacy bare array is migrated on the next write.
// A corrupt file is copied aside and never silently discarded, but it also
// does not prevent the app from starting: the app pauses with a status the
// user can inspect with `xmonad recover --report`.
import Foundation

struct RecoveryEntry: Codable, Equatable {
  var token: String, pid: Int32, launch: Double, bundle: String
  var identifier: String, title: String, frame: Rect
}

struct RecoveryEnvelope: Codable {
  var version: Int
  var entries: [RecoveryEntry]
}

struct RecoveryReport: Codable {
  var version: Int?
  var entries: Int
  var warning: String?
  var error: String?
  var quarantine: String?
}

// The journal, session and diagnostic files carry window titles and frames.
func writePrivate(_ data: Data, to url: URL) throws {
  try data.write(to: url, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

final class RecoveryJournal {
  static let currentVersion = 1
  let url: URL
  private(set) var entries: [RecoveryEntry]
  private(set) var formatVersion: Int?
  private(set) var loadWarning: String?
  private(set) var loadError: String?
  private(set) var quarantineURL: URL?

  init(_ url: URL, quarantine: Bool = true) {
    self.url = url
    self.entries = []
    guard FileManager.default.fileExists(atPath: url.path) else {
      formatVersion = Self.currentVersion
      return
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      loadError = "cannot read recovery journal: \(error)"
      return
    }
    if let envelope = try? JSONDecoder().decode(RecoveryEnvelope.self, from: data) {
      formatVersion = envelope.version
      if envelope.version == Self.currentVersion {
        entries = envelope.entries
      } else {
        loadError = "unsupported recovery journal version \(envelope.version)"
      }
      return
    }
    if let legacyEntries = try? JSONDecoder().decode([RecoveryEntry].self, from: data) {
      entries = legacyEntries
      formatVersion = 0
      loadWarning = "migrated the legacy array recovery journal"
      // Migrate now so a later crash cannot leave the format ambiguous. A
      // failed migration keeps the old entries in memory and is reported.
      do {
        try persist(entries)
      } catch {
        loadWarning = "legacy recovery journal could not be migrated: \(error)"
      }
      return
    }
    // Preserve the bytes instead of deleting evidence. The app stays paused
    // until the user decides what to do, but it can start and report. A
    // read-only report does not create another copy on every invocation.
    if let existing = existingQuarantine(), (try? Data(contentsOf: existing)) == data {
      quarantineURL = existing
    } else if quarantine {
      let stamp = Int(Date().timeIntervalSince1970)
      let base = url.deletingPathExtension().lastPathComponent
      var destination = url.deletingLastPathComponent()
        .appendingPathComponent("\(base).corrupt-\(stamp).json")
      var suffix = 1
      while FileManager.default.fileExists(atPath: destination.path) {
        destination = url.deletingLastPathComponent()
          .appendingPathComponent("\(base).corrupt-\(stamp)-\(suffix).json")
        suffix += 1
      }
      do {
        try FileManager.default.copyItem(at: url, to: destination)
        quarantineURL = destination
      } catch {
        loadWarning = "could not copy the corrupt recovery journal: \(error)"
      }
    }
    loadError = "recovery journal is not valid JSON in a known format"
  }

  private func existingQuarantine() -> URL? {
    let directory = url.deletingLastPathComponent()
    let prefix = url.deletingPathExtension().lastPathComponent + ".corrupt-"
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return nil }
    return files.filter { $0.lastPathComponent.hasPrefix(prefix) }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
      .first
  }

  var needsAttention: Bool { loadError != nil }

  private func persist(_ next: [RecoveryEntry]) throws {
    let data = try JSONEncoder().encode(
      RecoveryEnvelope(version: Self.currentVersion, entries: next))
    try writePrivate(data, to: url)
    entries = next
    formatVersion = Self.currentVersion
  }

  func add(_ entry: RecoveryEntry) throws {
    guard !needsAttention else {
      throw NSError(
        domain: "XMonadMac.Recovery", code: 1,
        userInfo: [NSLocalizedDescriptionKey: loadError ?? "recovery journal needs attention"])
    }
    try persist(entries + [entry])
  }

  func remove(_ token: String) throws {
    guard !needsAttention else {
      throw NSError(
        domain: "XMonadMac.Recovery", code: 1,
        userInfo: [NSLocalizedDescriptionKey: loadError ?? "recovery journal needs attention"])
    }
    try persist(entries.filter { $0.token != token })
  }

  func report() -> RecoveryReport {
    RecoveryReport(
      version: formatVersion, entries: entries.count, warning: loadWarning,
      error: loadError, quarantine: quarantineURL?.path)
  }
}
