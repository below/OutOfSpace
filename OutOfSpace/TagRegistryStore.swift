import Foundation
import Combine

// MARK: - Tag Registry

struct TagAlias: Codable, Equatable {
    var name: String
    var notes: String? = nil
}

@MainActor
final class TagRegistryStore: ObservableObject {
    @Published private(set) var registry: [String: TagAlias] = [:]

    private let defaultsKey = "ToyPad.TagRegistry.v1"

    /// Seed with the user’s currently known physical tags.
    private let seed: [String: TagAlias] = [
        "04DCF57A5C4980": .init(name: "Gandalf"),
        "0439749A0C4081": .init(name: "Wyldstyle"),
        "0450BEA2714081": .init(name: "Batman"),
        "04B35F329A4080": .init(name: "Batmobile"),
        "04F1AAE2284980": .init(name: "Portal Companion Cube"),
        "0457E35A804980": .init(name: "Portal Sentry Turret"),
        "0427A57AA44881": .init(name: "Portal Chell")
    ]

    init() {
        load()
        mergeSeedIfNeeded()
    }

    func displayName(for uidHex: String?) -> String {
        guard let uidHex, !uidHex.isEmpty else { return "—" }
        if let alias = registry[uidHex] { return alias.name }
        let suffix = String(uidHex.suffix(6))
        return "Unknown · …\(suffix)"
    }

    func setName(_ name: String, for uidHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        registry[uidHex] = TagAlias(name: trimmed)
        save()
    }

    func remove(uidHex: String) {
        registry.removeValue(forKey: uidHex)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            registry = [:]
            return
        }
        do {
            registry = try JSONDecoder().decode([String: TagAlias].self, from: data)
        } catch {
            registry = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(registry)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // ignore
        }
    }

    private func mergeSeedIfNeeded() {
        var changed = false
        for (k, v) in seed where registry[k] == nil {
            registry[k] = v
            changed = true
        }
        if changed { save() }
    }
}
