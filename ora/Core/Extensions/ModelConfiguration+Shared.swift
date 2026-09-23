import Foundation
import SwiftData

extension ModelConfiguration {
    /// Shared model configuration for the main Ora database
    static func oraDatabase(isPrivate: Bool = false) -> ModelConfiguration {
        if isPrivate {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            return ModelConfiguration(
                "OraData",
                schema: Schema([TabContainer.self, History.self, Download.self]),
                url: URL.applicationSupportDirectory.appending(path: "Ora/OraData.sqlite")
            )
        }
    }

    /// Creates a ModelContainer using the standard Ora database configuration
    static func createOraContainer(isPrivate: Bool = false) throws -> ModelContainer {
        // SwiftData does not create missing parent folders, so a first launch would fail without this.
        if !isPrivate {
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory.appending(path: "Ora"),
                withIntermediateDirectories: true
            )
        }
        return try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: oraDatabase(isPrivate: isPrivate)
        )
    }
}
