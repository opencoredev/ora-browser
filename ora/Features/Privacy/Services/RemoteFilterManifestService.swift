import CryptoKit
import Foundation

struct RemoteFilterManifest: Codable, Equatable {
    struct List: Codable, Equatable {
        struct Shard: Codable, Equatable {
            let path: String
            let sha256: String
            let ruleCount: Int
        }
        let id: String
        let sourceURL: String
        let sourceVersion: String
        let droppedRuleCount: Int
        let shards: [Shard]
    }
    let schemaVersion: Int
    let generatedAt: String
    let converter: String
    let lists: [List]

    func changedListIDs(comparedWith other: RemoteFilterManifest) -> Set<String> {
        let old = Dictionary(uniqueKeysWithValues: other.lists.map { ($0.id, $0) })
        return Set(lists.filter { old[$0.id] != $0 }.map(\.id))
    }
}

enum RemoteFilterManifestError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case checksumMismatch(String)
}

struct RemoteFilterManifestService {
    static let defaultManifestURL = URL(string: "https://github.com/the-ora/browser/releases/download/adblock-latest/manifest.json")!
    private let session: URLSession
    private let manifestURL: URL

    init(session: URLSession = .shared, manifestURL: URL = RemoteFilterManifestService.defaultManifestURL) {
        self.session = session
        self.manifestURL = manifestURL
    }

    func fetchManifest() async throws -> RemoteFilterManifest {
        let (data, response) = try await session.data(from: manifestURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteFilterManifestError.invalidResponse }
        return try JSONDecoder().decode(RemoteFilterManifest.self, from: data)
    }

    static func verify(data: Data, sha256: String) -> Bool {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(sha256) == .orderedSame
    }

    func sync(_ manifest: RemoteFilterManifest, listIDs: Set<String>, artifactStore: ContentBlockerArtifactStore) async throws -> Set<String> {
        var changed = Set<String>()
        for list in manifest.lists where listIDs.contains(list.id) {
            var jsonShards: [String] = []
            var total = 0
            for shard in list.shards {
                let data = try await fetchShard(shard, relativeTo: list)
                guard let json = String(data: data, encoding: .utf8) else { throw RemoteFilterManifestError.invalidResponse }
                jsonShards.append(json)
                total += shard.ruleCount
            }
            let digest = list.shards.map(\.sha256).joined()
            let revision = String(digest.prefix(16))
            if !artifactStore.hasCompiledArtifacts(for: list.id, revision: revision) {
                try artifactStore.storeCompiledArtifacts(jsonShards: jsonShards, coverage: FilterListCoverage(totalRuleCount: total, convertedRuleCount: total, skippedRuleCount: list.droppedRuleCount, safariRuleCount: total, shardCount: jsonShards.count), for: list.id, revision: revision)
                changed.insert(list.id)
            }
        }
        return changed
    }

    func fetchShard(_ shard: RemoteFilterManifest.List.Shard, relativeTo manifest: RemoteFilterManifest.List, baseURL: URL? = nil) async throws -> Data {
        let url = (baseURL ?? manifestURL.deletingLastPathComponent()).appendingPathComponent(shard.path)
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteFilterManifestError.invalidResponse }
        guard Self.verify(data: data, sha256: shard.sha256) else {
            throw RemoteFilterManifestError.checksumMismatch(shard.path)
        }
        return data
    }
}
