import AppKit

enum FolderIndicatorTests {
    static func run() {
        precondition(FolderIndicator.badge(for: 0) == "0")
        precondition(FolderIndicator.badge(for: -1) == "0")
        precondition(FolderIndicator.badge(for: 1) == "1")
        precondition(FolderIndicator.badge(for: 42) == "42")
        precondition(FolderIndicator.badge(for: 100) == "99+")
        let selected: Set<String> = ["docker", "holdimg", "quit-app"]
        precondition(FolderIndicator.count(availableIDs: ["docker", "holdimg", "docker", "stats"], selectedIDs: selected) == 2)
        precondition(FolderIndicator.count(availableIDs: ["docker"], selectedIDs: selected) == 1, "Quit apps do not remain in the count")
        precondition(FolderIndicator.count(availableIDs: ["docker"], selectedIDs: []) == 0)
        for count in [0, 1, 4, 12, 99, 100] {
            let image = FolderIndicator.image(count: count)
            precondition(image.isTemplate && image.size == FolderIndicator.size, "Count changes must not resize the status item")
            precondition(image.tiffRepresentation != nil, "Every indicator must render")
        }
        print("PASS: folder indicator counts live items, caps its badge, and retains fixed template size")
    }
}
