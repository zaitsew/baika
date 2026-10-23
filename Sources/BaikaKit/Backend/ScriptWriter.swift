import Foundation

/// Streams text from a model. The accounts bridge implements it with the hub's `ai` stream.
public protocol ScriptBackend: Sendable {
    /// Deltas of assistant text. Throws `BackendFailure` for anything the app can act on.
    func stream(model: String, system: String, user: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, any Error>
}

public enum ScriptEvent: Sendable, Equatable {
    /// A model call began. A second one means the primary model was refused.
    case model(String)
    case delta(String)
}

/// Writes the story: the dearer model first, the cheaper one if the hub refuses the first
/// before any text arrived.
public struct ScriptWriter: Sendable {
    private let backend: any ScriptBackend

    public init(backend: any ScriptBackend) {
        self.backend = backend
    }

    public func write(_ request: StoryRequest) -> AsyncThrowingStream<ScriptEvent, any Error> {
        let backend = backend
        let system = StoryPrompt.system(for: request)
        let user = StoryPrompt.user(for: request)
        let limit = StoryPrompt.maxOutputTokens(for: request.length)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var models = [StoryPrompt.primaryModel, StoryPrompt.fallbackModel]
                while !models.isEmpty {
                    let model = models.removeFirst()
                    continuation.yield(.model(model))
                    var received = false
                    do {
                        for try await delta in backend.stream(model: model, system: system, user: user, maxOutputTokens: limit) {
                            received = true
                            continuation.yield(.delta(delta))
                        }
                        continuation.finish()
                        return
                    } catch let failure as BackendFailure where !received && !models.isEmpty && ModelFallback.shouldFallBack(after: failure) {
                        continue
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
