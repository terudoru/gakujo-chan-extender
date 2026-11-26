import Foundation

func findIdenticalDownload(in directory: URL, desiredName: String, newFile: URL) -> URL? {
  let name = desiredName as NSString
  let ext = name.pathExtension
  let base = ext.isEmpty ? desiredName : name.deletingPathExtension
  var candidateNames: Set<String> = [desiredName.lowercased()]
  for index in 1...999 {
    let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
    candidateNames.insert(candidate.lowercased())
  }
  let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
  guard let size = try? newFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        let entries = try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: Array(keys)
        ) else {
    return nil
  }
  for candidate in entries {
    guard candidate.standardizedFileURL != newFile.standardizedFileURL,
          candidateNames.contains(candidate.lastPathComponent.lowercased()),
          let values = try? candidate.resourceValues(forKeys: keys),
          values.isRegularFile == true, values.isSymbolicLink != true,
          values.fileSize == size else {
      continue
    }
    // Unreadable candidates cannot prove a duplicate; keep the new file.
    if (try? filesHaveSameContent(newFile, candidate)) == true {
      return candidate
    }
  }
  return nil
}

private func filesHaveSameContent(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
  let first = try FileHandle(forReadingFrom: firstURL)
  defer { try? first.close() }
  let second = try FileHandle(forReadingFrom: secondURL)
  defer { try? second.close() }
  while true {
    guard let chunk = try first.read(upToCount: 64 * 1024), !chunk.isEmpty else {
      return (try second.read(upToCount: 1))?.isEmpty ?? true
    }
    var other = Data()
    while other.count < chunk.count {
      guard let part = try second.read(upToCount: chunk.count - other.count),
            !part.isEmpty else {
        return false
      }
      other.append(part)
    }
    if chunk != other {
      return false
    }
  }
}

func uniqueDownloadFileName(desiredName: String, existingLowercaseNames: Set<String>) -> String {
  if !existingLowercaseNames.contains(desiredName.lowercased()) {
    return desiredName
  }

  let nsName = desiredName as NSString
  let ext = nsName.pathExtension
  let base = ext.isEmpty ? desiredName : nsName.deletingPathExtension
  var index = 1
  while true {
    let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
    if !existingLowercaseNames.contains(candidate.lowercased()) {
      return candidate
    }
    index += 1
  }
}

func sanitizeDownloadName(_ raw: String?) -> String {
  let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    .union(.controlCharacters)
  let trimmingCharacters = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "."))
  let cleaned = (raw ?? "")
    .components(separatedBy: invalid)
    .joined()
    .replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    .trimmingCharacters(in: trimmingCharacters)
  return cleaned == "." || cleaned == ".." ? "" : cleaned
}

func isDownloadPathWithinRoot(_ url: URL, of root: URL) -> Bool {
  let rootPath = root.standardizedFileURL.path
  let path = url.standardizedFileURL.path
  return path == rootPath || path.hasPrefix(rootPath + "/")
}
