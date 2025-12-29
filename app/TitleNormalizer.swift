// TitleNormalizer.swift
// vulpes-browser
//
// Heuristic title cleanup for readable, short tab labels.

import Foundation

enum TitleNormalizer {
    static func cleanTitle(from text: String, url: String) -> String {
        let firstLine = extractFirstMeaningfulLine(from: text)
        let base = firstLine.isEmpty ? hostFromURL(url) : firstLine
        return normalizeTitle(base)
    }

    private static func extractFirstMeaningfulLine(from text: String) -> String {
        for rawLine in text.split(separator: "\n") {
            let cleaned = stripControlCharacters(String(rawLine))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return ""
    }

    private static func normalizeTitle(_ title: String) -> String {
        var result = title
        let separators = [" | ", " — ", " - ", " · ", " :: ", " : "]
        for sep in separators {
            if let range = result.range(of: sep) {
                result = String(result[..<range.lowerBound])
                break
            }
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > 48 {
            let idx = result.index(result.startIndex, offsetBy: 48)
            result = String(result[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func hostFromURL(_ url: String) -> String {
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }

    private static func stripControlCharacters(_ text: String) -> String {
        return String(text.unicodeScalars.filter { $0.value >= 0x20 })
    }
}
