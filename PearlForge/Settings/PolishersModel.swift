import Foundation
import Observation

/// State behind the AI tab: each service's key and models, the model chosen
/// for each, and which service polishes by default. Keys live in the
/// Keychain; the choices aren't secret, so they live in UserDefaults.
@MainActor
@Observable
final class PolishersModel {
    private static let activeKey = "polisher"
    private static func modelKey(_ provider: PolisherProvider) -> String { "polisher.model.\(provider.rawValue)" }
    private static func modelNameKey(_ provider: PolisherProvider) -> String { "polisher.modelName.\(provider.rawValue)" }
    private static let readingModelKey = "reading.model"
    private static let readingModelNameKey = "reading.modelName"

    /// Find reading uses Claude Sonnet 5.5 unless you choose otherwise: it costs
    /// about half as much per search as Opus 5.5.
    static let defaultReadingModel = "claude-sonnet-5-5"

    private(set) var status: [PolisherProvider: KeyStatus] = [:]
    private(set) var models: [PolisherProvider: [AIModel]] = [:]
    private(set) var selectedModels: [PolisherProvider: String] = [:]
    /// Remembered so the chosen model can be named before the list loads.
    private var selectedModelNames: [PolisherProvider: String] = [:]

    /// The Claude model that finds reading for your recordings. Separate from
    /// the polishing model, so each can be chosen on its own.
    private(set) var readingModel: String
    private var readingModelName: String?

    /// The service that polishes new recordings and new pearls by default.
    var active: PolisherProvider {
        didSet { UserDefaults.standard.set(active.rawValue, forKey: Self.activeKey) }
    }

    init() {
        active = UserDefaults.standard.string(forKey: Self.activeKey).flatMap(PolisherProvider.init) ?? .anthropic
        readingModel = UserDefaults.standard.string(forKey: Self.readingModelKey) ?? Self.defaultReadingModel
        readingModelName = UserDefaults.standard.string(forKey: Self.readingModelNameKey)
            ?? (readingModel == Self.defaultReadingModel ? "Claude Sonnet 5.5" : nil)
        for provider in PolisherProvider.allCases {
            status[provider] = KeychainStore.read(provider.credential) == nil ? .notSet : .saved
            selectedModels[provider] = UserDefaults.standard.string(forKey: Self.modelKey(provider))
                ?? provider.defaultModel
            selectedModelNames[provider] = UserDefaults.standard.string(forKey: Self.modelNameKey(provider))
                ?? (provider == .anthropic ? "Claude Opus 5.5" : nil)
        }
    }

    // MARK: Choices

    /// Has a key and a model, so it can polish.
    func isReady(_ provider: PolisherProvider) -> Bool {
        status[provider] != .notSet && selectedModels[provider] != nil
    }

    func choice(for provider: PolisherProvider) -> PolisherChoice? {
        guard isReady(provider), let model = selectedModels[provider] else { return nil }
        return PolisherChoice(provider: provider, model: model)
    }

    /// The default polisher, if it's set up.
    var activeChoice: PolisherChoice? { choice(for: active) }

    var readyProviders: [PolisherProvider] {
        PolisherProvider.allCases.filter(isReady)
    }

    func selectModel(_ id: String, name: String? = nil, for provider: PolisherProvider) {
        selectedModels[provider] = id
        selectedModelNames[provider] = name
        UserDefaults.standard.set(id, forKey: Self.modelKey(provider))
        UserDefaults.standard.set(name, forKey: Self.modelNameKey(provider))
    }

    func selectReadingModel(_ id: String, name: String?) {
        readingModel = id
        readingModelName = name
        UserDefaults.standard.set(id, forKey: Self.readingModelKey)
        UserDefaults.standard.set(name, forKey: Self.readingModelNameKey)
    }

    /// "Claude Sonnet 5.5": the Find reading model's name.
    var readingModelLabel: String {
        models[.anthropic]?.first { $0.id == readingModel }?.name ?? readingModelName ?? readingModel
    }

    /// "Claude Opus 5.5" for a known model, else the model id itself.
    func modelName(_ id: String, for provider: PolisherProvider) -> String {
        if let listed = models[provider]?.first(where: { $0.id == id }) {
            return listed.name
        }
        if selectedModels[provider] == id, let saved = selectedModelNames[provider] {
            return saved
        }
        return id
    }

    /// "Claude · Claude Opus 5.5"
    func label(for choice: PolisherChoice) -> String {
        "\(choice.provider.name) · \(modelName(choice.model, for: choice.provider))"
    }

    // MARK: Keys

    /// Checks any saved key that hasn't been checked yet this launch.
    func checkSavedKeys() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in PolisherProvider.allCases where status[provider] == .saved {
                group.addTask { await self.check(provider) }
            }
        }
    }

    /// Saves a newly typed key (nil keeps the current one) and, for Claude,
    /// the optional workspace ID; then checks the key and loads the models.
    func saveKey(_ key: String?, workspaceID: String, for provider: PolisherProvider) throws {
        if let key {
            try KeychainStore.save(key, for: provider.credential)
        }
        if provider == .anthropic {
            if workspaceID.isEmpty {
                KeychainStore.delete(.anthropicWorkspaceID)
            } else {
                try KeychainStore.save(workspaceID, for: .anthropicWorkspaceID)
            }
        }
        status[provider] = .saved
        models[provider] = nil
        Task { await check(provider) }
    }

    func removeKey(for provider: PolisherProvider) {
        KeychainStore.delete(provider.credential)
        status[provider] = .notSet
        models[provider] = nil
        if active == provider, let other = readyProviders.first {
            active = other
        }
    }

    /// Checks the key and loads the service's models.
    func check(_ provider: PolisherProvider) async {
        guard let key = KeychainStore.read(provider.credential) else {
            status[provider] = .notSet
            return
        }
        status[provider] = .checking
        do {
            let list: [AIModel]
            switch provider {
            case .anthropic:
                list = try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                    .listModels()
            case .openai, .gemini, .openrouter:
                let client = OpenAICompatibleClient(provider: provider, apiKey: key)
                if provider == .openrouter {
                    try await client.checkKey()
                }
                list = try await client.listModels()
            }
            models[provider] = list
            status[provider] = .works
            if provider == .anthropic, let listed = list.first(where: { $0.id == readingModel }) {
                selectReadingModel(listed.id, name: listed.name)
            }
            if let selected = selectedModels[provider], let listed = list.first(where: { $0.id == selected }) {
                selectModel(listed.id, name: listed.name, for: provider)
            } else if selectedModels[provider] == nil, let suggested = suggestedModel(for: provider, in: list) {
                selectModel(suggested.id, name: suggested.name, for: provider)
            }
        } catch {
            status[provider] = .failed(error.localizedDescription)
        }
    }

    /// A sensible first pick until you choose: the newest full-size model.
    /// OpenRouter offers too many to guess, so you choose there.
    private func suggestedModel(for provider: PolisherProvider, in list: [AIModel]) -> AIModel? {
        switch provider {
        case .anthropic:
            return list.first { $0.id == PipelineConfig.refinementModel } ?? list.first
        case .openai:
            let small = ["mini", "nano", "preview"]
            return list.first { model in !small.contains { model.id.contains($0) } } ?? list.first
        case .gemini:
            return list.first { $0.id.contains("pro") && !$0.id.contains("preview") }
                ?? list.first { $0.id.contains("gemini") }
        case .openrouter:
            return nil
        }
    }
}
