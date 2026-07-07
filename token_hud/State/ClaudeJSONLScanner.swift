// token_hud/State/ClaudeJSONLScanner.swift
import Foundation
import os

/// Scans Claude Code's local JSONL session files under `~/.claude/projects/`
/// and aggregates token usage and costs.
///
/// Reference: ccusage (Rust) and claude-usage (Python) both use this approach.
/// Only entries with `type == "assistant"` and non-zero token usage are counted.
enum ClaudeJSONLScanner {
    private static let logger = Logger.apiPlatform

    // MARK: - Result types

    struct Result {
        let totalInputTokens: Double
        let totalOutputTokens: Double
        let totalCacheCreationTokens: Double
        let totalCacheReadTokens: Double
        let totalCostUSD: Double
        let sessionCount: Int
        let latestModel: String?
        let earliestTimestamp: String?
        let latestTimestamp: String?
        let modelBreakdown: [ModelBreakdown]
        let projectBreakdown: [ProjectBreakdown]
    }

    struct ModelBreakdown {
        let model: String
        let inputTokens: Double
        let outputTokens: Double
        let entries: Int

        var totalTokens: Double { inputTokens + outputTokens }
    }

    struct ProjectBreakdown {
        let project: String
        let inputTokens: Double
        let outputTokens: Double
        let entries: Int

        var totalTokens: Double { inputTokens + outputTokens }
    }

    // MARK: - Accumulator (internal)

    private struct Accumulator {
        var totalInput: Double = 0
        var totalOutput: Double = 0
        var totalCacheCreation: Double = 0
        var totalCacheRead: Double = 0
        var totalCost: Double = 0
        var sessionIDs = Set<String>()
        var earliestTimestamp: String = ""
        var latestTimestamp: String = ""
        var latestModel: String?
        var modelStats: [String: (input: Double, output: Double, entries: Int)] = [:]
        var projectStats: [String: (input: Double, output: Double, entries: Int)] = [:]
        var entryCount: Int = 0

        mutating func addEntry(
            inputTokens: Double,
            outputTokens: Double,
            cacheCreation: Double,
            cacheRead: Double,
            costUSD: Double,
            timestamp: String,
            sessionID: String,
            model: String?,
            project: String
        ) {
            totalInput += inputTokens
            totalOutput += outputTokens
            totalCacheCreation += cacheCreation
            totalCacheRead += cacheRead
            if costUSD > 0 { totalCost += costUSD }
            if !sessionID.isEmpty { sessionIDs.insert(sessionID) }

            if !timestamp.isEmpty {
                if earliestTimestamp.isEmpty || timestamp < earliestTimestamp {
                    earliestTimestamp = timestamp
                }
                if timestamp > latestTimestamp {
                    latestTimestamp = timestamp
                    latestModel = model
                }
            }

            let m = model ?? "unknown"
            var ms = modelStats[m] ?? (0, 0, 0)
            ms.input += inputTokens
            ms.output += outputTokens
            ms.entries += 1
            modelStats[m] = ms

            let p = project.isEmpty ? "unknown" : project
            var ps = projectStats[p] ?? (0, 0, 0)
            ps.input += inputTokens
            ps.output += outputTokens
            ps.entries += 1
            projectStats[p] = ps

            entryCount += 1
        }

        func toResult() -> Result {
            Result(
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                totalCacheCreationTokens: totalCacheCreation,
                totalCacheReadTokens: totalCacheRead,
                totalCostUSD: totalCost,
                sessionCount: sessionIDs.count,
                latestModel: latestModel,
                earliestTimestamp: earliestTimestamp.isEmpty ? nil : earliestTimestamp,
                latestTimestamp: latestTimestamp.isEmpty ? nil : latestTimestamp,
                modelBreakdown: modelStats
                    .map { ModelBreakdown(model: $0.key, inputTokens: $0.value.input, outputTokens: $0.value.output, entries: $0.value.entries) }
                    .sorted { $0.totalTokens > $1.totalTokens },
                projectBreakdown: projectStats
                    .map { ProjectBreakdown(project: $0.key, inputTokens: $0.value.input, outputTokens: $0.value.output, entries: $0.value.entries) }
                    .sorted { $0.totalTokens > $1.totalTokens }
            )
        }
    }

    // MARK: - Public API

    /// Scan `~/.claude/projects/` for JSONL files modified within `daysBack` days.
    /// Returns nil if no data found.
    static func scan(daysBack: Int = 7) -> Result? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            return nil
        }

        let cutoff = Date().addingTimeInterval(-Double(daysBack * 86400))
        var acc = Accumulator()

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var fileCount = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Skip files older than cutoff
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attrs.contentModificationDate,
               modDate < cutoff {
                continue
            }

            fileCount += 1
            let project = extractProject(from: fileURL)
            scanFile(fileURL, project: project, acc: &acc)
        }

        guard acc.entryCount > 0 else {
            logger.debug("Claude JSONL scan: no usage entries found in \(fileCount) files")
            return nil
        }

        logger.info("Claude JSONL scan: \(acc.entryCount) entries in \(fileCount) files, \(acc.sessionIDs.count) sessions, total tokens: \(Int(acc.totalInput + acc.totalOutput))")

        return acc.toResult()
    }

    // MARK: - File scanning

    private static func scanFile(_ url: URL, project: String, acc: inout Accumulator) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }

        var lineStart = 0
        let bytes = [UInt8](data)

        for i in 0..<bytes.count {
            if bytes[i] == 0x0A { // newline
                let lineData = Data(bytes[lineStart..<i])
                lineStart = i + 1
                processLine(lineData, project: project, acc: &acc)
            }
        }
        // Handle last line without trailing newline
        if lineStart < bytes.count {
            let lineData = Data(bytes[lineStart..<bytes.count])
            processLine(lineData, project: project, acc: &acc)
        }
    }

    private static func processLine(_ data: Data, project: String, acc: inout Accumulator) {
        // Quick pre-filter: must contain "usage" to be worth parsing
        guard let str = String(data: data, encoding: .utf8),
              str.contains("\"usage\""),
              str.contains("\"assistant\"")
        else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Must be type == "assistant"
        guard json["type"] as? String == "assistant" else { return }

        // Extract message.usage
        guard let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return }

        let inputTokens = usage["input_tokens"] as? Double ?? 0
        let outputTokens = usage["output_tokens"] as? Double ?? 0

        // Must have actual token usage
        guard inputTokens > 0 || outputTokens > 0 else { return }

        let model = message["model"] as? String
        if model == "<synthetic>" { return }

        acc.addEntry(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreation: usage["cache_creation_input_tokens"] as? Double ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Double ?? 0,
            costUSD: json["costUSD"] as? Double ?? 0,
            timestamp: json["timestamp"] as? String ?? "",
            sessionID: json["sessionId"] as? String ?? "",
            model: model,
            project: project
        )
    }

    // MARK: - Helpers

    /// Extract project name from JSONL file path.
    /// Path format: ~/.claude/projects/<project>/<session>.jsonl
    private static func extractProject(from url: URL) -> String {
        let components = url.pathComponents
        // Find "projects" component and take the next one
        if let projectsIndex = components.lastIndex(of: "projects"),
           projectsIndex + 1 < components.count - 1 { // -1 to exclude the file itself
            return components[projectsIndex + 1]
        }
        return url.deletingLastPathComponent().lastPathComponent
    }
}
