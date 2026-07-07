// token_hud/State/ProviderStatusMonitor.swift
import Foundation
import Observation
import os

/// Monitors provider status by polling status pages or health endpoints.
@Observable
@MainActor
final class ProviderStatusMonitor {
    private static let logger = Logger.apiPlatform

    typealias Status = ProviderAvailabilityStatus

    private(set) var statuses: [String: Status] = [:]

    private var timer: Timer?
    private let interval: TimeInterval = 300 // 5 minutes

    func start() {
        timer?.invalidate()
        Task { await checkAll() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func status(for providerID: String) -> Status {
        statuses[providerID] ?? .unknown
    }

    private func checkAll() async {
        await withTaskGroup(of: (String, Status).self) { group in
            // OpenAI status page
            group.addTask { await self.checkStatusPage(id: "openai", url: "https://status.openai.com/api/v2/status.json") }
            // Anthropic status page
            group.addTask { await self.checkStatusPage(id: "anthropic", url: "https://status.anthropic.com/api/v2/status.json") }
            // DeepSeek: check balance endpoint reachability
            group.addTask { await self.checkEndpoint(id: "deepseek", url: "https://api.deepseek.com/user/balance") }
            // Moonshot: check balance endpoint
            group.addTask { await self.checkEndpoint(id: "moonshot", url: "https://api.moonshot.cn/v1/users/me/balance") }
            // OpenRouter: check credits endpoint
            group.addTask { await self.checkEndpoint(id: "openrouter", url: "https://openrouter.ai/api/v1/credits") }
            // Qwen: check balance endpoint
            group.addTask { await self.checkEndpoint(id: "qwen", url: "https://dashscope.aliyuncs.com/api/v1/user/balance") }
            // MiniMax: check models endpoint
            group.addTask { await self.checkEndpoint(id: "minimax", url: "https://api.minimax.io/v1/models") }
            // MiMo: check models endpoint
            group.addTask { await self.checkEndpoint(id: "mimo", url: "https://api.xiaomimimo.com/v1/models") }

            for await (id, status) in group {
                statuses[id] = status
            }
        }
        Self.logger.debug("Provider status check complete: \(self.statuses.map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ", "))")
    }

    /// Check a statuspage.io-style status endpoint.
    private func checkStatusPage(id: String, url: String) async -> (String, Status) {
        guard let urlObj = URL(string: url) else { return (id, .unknown) }
        var request = URLRequest(url: urlObj)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else { return (id, .down) }

            // Statuspage.io format: { "status": { "indicator": "none|minor|major|critical" } }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? [String: Any],
               let indicator = status["indicator"] as? String {
                return (id, ProviderStatusPolicy.statusPageStatus(indicator: indicator))
            }
            return (id, .operational) // Valid response but unexpected format
        } catch {
            return (id, .unknown)
        }
    }

    /// Check if an API endpoint is reachable (returns any HTTP response).
    private func checkEndpoint(id: String, url: String) async -> (String, Status) {
        guard let urlObj = URL(string: url) else { return (id, .unknown) }
        var request = URLRequest(url: urlObj)
        request.timeoutInterval = 10
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (id, .unknown) }

            return (id, ProviderStatusPolicy.endpointStatus(forHTTPStatusCode: httpResponse.statusCode))
        } catch {
            return (id, .down)
        }
    }
}
