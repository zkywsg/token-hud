import Testing
import Foundation
@testable import token_hudCore

@Suite("StateModel")
struct StateModelTests {

    let fullStateJSON = """
    {
      "version": 1,
      "updatedAt": "2026-04-01T10:00:00Z",
      "services": {
        "claude": {
          "label": "Claude Max",
          "quotas": [
            { "type": "time", "total": 18000, "used": 3600, "unit": "seconds", "resetsAt": "2026-04-01T15:00:00Z" },
            { "type": "tokens", "total": 1000000, "used": 150000, "unit": "tokens" }
          ],
          "currentSession": {
            "id": "sess-abc",
            "startedAt": "2026-04-01T09:50:00Z",
            "tokens": 1500,
            "time": 142.5
          }
        },
        "openai": {
          "label": "OpenAI",
          "quotas": [
            { "type": "money", "total": 20.0, "used": 1.5, "unit": "USD" }
          ],
          "currentSession": null
        }
      }
    }
    """

    @Test func decodesVersion() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        #expect(state.version == 1)
    }

    @Test func decodesServices() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        #expect(state.services.count == 2)
        #expect(state.services["claude"]?.label == "Claude Max")
    }

    @Test func decodesQuotas() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        let quotas = state.services["claude"]!.quotas
        #expect(quotas.count == 2)
        #expect(quotas[0].type == .time)
        #expect(quotas[0].total == 18000)
        #expect(quotas[0].used == 3600)
        #expect(quotas[0].resetsAt == "2026-04-01T15:00:00Z")
    }

    @Test func decodesCurrentSession() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        let session = state.services["claude"]!.currentSession
        #expect(session != nil)
        #expect(session?.id == "sess-abc")
        #expect(session?.tokens == 1500)
    }

    @Test func decodesNullSession() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        #expect(state.services["openai"]!.currentSession == nil)
    }

    @Test func decodesAllQuotaTypes() throws {
        for typeStr in ["time", "tokens", "money", "requests",
                        "input_tokens", "output_tokens", "daily_tokens",
                        "monthly_tokens", "daily_requests", "monthly_requests", "cost_spent"] {
            let json = """
            {"version":1,"updatedAt":"2026-04-01T00:00:00Z","services":{"s":{"label":"S","quotas":[{"type":"\(typeStr)","total":100,"used":10,"unit":"x"}],"currentSession":null}}}
            """
            let state = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))
            #expect(state.services["s"]?.quotas.first != nil)
        }
    }

    @Test func sessionSnapshotNewFieldsNilWhenAbsent() throws {
        let json = """
        {"version":1,"updatedAt":"2026-04-01T00:00:00Z","services":{"s":{"label":"S","quotas":[],"currentSession":{"id":"x","startedAt":"2026-04-01T00:00:00Z","tokens":100}}}}
        """
        let state = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))
        let session = state.services["s"]?.currentSession
        #expect(session?.tokens == 100)
        #expect(session?.inputTokens == nil)
        #expect(session?.outputTokens == nil)
        #expect(session?.costSpent == nil)
    }

    @Test func sessionSnapshotNewFieldsDecodeWhenPresent() throws {
        let json = """
        {"version":1,"updatedAt":"2026-04-01T00:00:00Z","services":{"s":{"label":"S","quotas":[],"currentSession":{"id":"x","startedAt":"2026-04-01T00:00:00Z","tokens":100,"inputTokens":60,"outputTokens":40,"costSpent":0.55}}}}
        """
        let state = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))
        let session = state.services["s"]?.currentSession
        #expect(session?.inputTokens == 60)
        #expect(session?.outputTokens == 40)
        #expect(session?.costSpent == 0.55)
    }

    @Test func serviceErrorIsNilWhenKeyAbsent() throws {
        let state = try JSONDecoder().decode(StateFile.self, from: Data(fullStateJSON.utf8))
        #expect(state.services["claude"]?.error == nil)
    }

    @Test func serviceErrorDecodesWhenPresent() throws {
        let json = """
        {"version":1,"updatedAt":"2026-04-01T00:00:00Z","services":{"codex":{"label":"Codex","quotas":[],"currentSession":null,"error":"tokenExpired"}}}
        """
        let state = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))
        #expect(state.services["codex"]?.error == "tokenExpired")
    }

    @Test func modelBreakdownNilWhenAbsent() throws {
        let json = """
        {"id":"x","startedAt":"2026-04-01T00:00:00Z"}
        """
        let session = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        #expect(session.modelBreakdown == nil)
    }

    @Test func modelBreakdownDecodesWhenPresent() throws {
        let json = """
        {"id":"x","startedAt":"2026-04-01T00:00:00Z","modelBreakdown":[{"model":"claude-sonnet-4","inputTokens":1000,"outputTokens":500,"costSpent":0.05,"requests":2}]}
        """
        let session = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        #expect(session.modelBreakdown?.count == 1)
        #expect(session.modelBreakdown?.first?.model == "claude-sonnet-4")
        #expect(session.modelBreakdown?.first?.inputTokens == 1000)
    }
}
