import Foundation

struct ReturnPlacement: Codable {
    // nil means the folder spacer. IDs survive Control Center recreating windows.
    let neighborID: String?
    let after: Bool

    static func load() -> [String: ReturnPlacement] {
        guard let data = UserDefaults.standard.data(forKey: "temporaryPlacements.v1") else { return [:] }
        return (try? JSONDecoder().decode([String: ReturnPlacement].self, from: data)) ?? [:]
    }
}
