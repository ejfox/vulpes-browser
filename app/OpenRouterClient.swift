// OpenRouterClient.swift
// vulpes-browser
//
// Minimal OpenRouter client for micro LLM title cleanup.

import Foundation

enum OpenRouterClient {
    private static var modelIndex: Int = 0
    private static let modelQueue = DispatchQueue(label: "vulpes.openrouter.models")
    private static var lastRequestTime: CFAbsoluteTime = 0

    static func generateOneWordTitle(
        from title: String,
        url: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let config = VulpesConfig.shared
        guard config.openRouterEnabled, !config.openRouterApiKey.isEmpty else {
            completion(.failure(OpenRouterError.disabled))
            return
        }

        guard shouldRequest(config: config) else {
            completion(.failure(OpenRouterError.rateLimited))
            return
        }

        let model = nextModel(from: config)
        guard let request = buildRequest(title: title, url: url, apiKey: config.openRouterApiKey, model: model) else {
            completion(.failure(OpenRouterError.invalidRequest))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(OpenRouterError.emptyResponse))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
                guard let content = decoded.choices.first?.message.content else {
                    completion(.failure(OpenRouterError.emptyResponse))
                    return
                }
                let oneWord = normalizeOneWord(content)
                if oneWord.isEmpty {
                    completion(.failure(OpenRouterError.emptyResponse))
                } else {
                    completion(.success(oneWord))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private static func shouldRequest(config: VulpesConfig) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = Double(config.openRouterMinIntervalMs) / 1000.0
        return modelQueue.sync {
            if now - lastRequestTime < minInterval {
                return false
            }
            lastRequestTime = now
            return true
        }
    }

    private static func nextModel(from config: VulpesConfig) -> String {
        let models = config.openRouterModels.isEmpty ? [config.openRouterModel] : config.openRouterModels
        return modelQueue.sync {
            if models.isEmpty {
                return config.openRouterModel
            }
            let model = models[modelIndex % models.count]
            modelIndex = (modelIndex + 1) % models.count
            return model
        }
    }

    private static func buildRequest(title: String, url: String, apiKey: String, model: String) -> URLRequest? {
        guard let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            return nil
        }

        let systemPrompt = """
        You are renaming browser tabs. Respond with a single short word (1-8 letters).
        No punctuation, no quotes, no extra words.
        """
        let userPrompt = "Title: \(title)\nURL: \(url)"

        let body = OpenRouterRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt),
            ],
            max_tokens: 6,
            temperature: 0.2
        )

        guard let bodyData = try? JSONEncoder().encode(body) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("vulpes-browser", forHTTPHeaderField: "X-Title")
        request.setValue("https://vulpes.local", forHTTPHeaderField: "HTTP-Referer")
        return request
    }

    private static func normalizeOneWord(_ text: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        let parts = trimmed.split(whereSeparator: { !$0.isLetter })
        return parts.first.map(String.init) ?? ""
    }
}

private struct OpenRouterRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let max_tokens: Int
    let temperature: Double
}

private struct OpenRouterResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

enum OpenRouterError: Error {
    case disabled
    case rateLimited
    case invalidRequest
    case emptyResponse
}
