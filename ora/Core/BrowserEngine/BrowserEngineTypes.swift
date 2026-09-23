import AppKit
import Foundation

enum BrowserWebsiteDataType: Hashable {
    case cookies
    case cache
    case all
}

enum BrowserUserScriptInjectionTime {
    case atDocumentStart
    case atDocumentEnd
}

/// The JavaScript world a script runs in. `.page` shares globals with the website.
/// `.isolated` shares the DOM but keeps its own globals, so pages cannot read or replace them.
enum BrowserScriptWorld {
    case page
    case isolated
}

struct BrowserUserScript {
    let name: String?
    let source: String
    let injectionTime: BrowserUserScriptInjectionTime
    let forMainFrameOnly: Bool
    var world: BrowserScriptWorld = .page
}

struct BrowserScriptMessage {
    let name: String
    let body: Any?
}

struct BrowserOpenPanelOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

enum BrowserPermissionKind {
    case mediaCapture
}

enum BrowserPermissionDecision {
    case grant
    case deny
}

struct BrowserNavigationAction {
    let request: URLRequest
    let modifierFlags: NSEvent.ModifierFlags
}

enum BrowserNavigationActionDisposition {
    case allow
    case cancel
    case openInNewTab
}

enum BrowserNavigationPhase {
    case started
    case committed
    case finished
}

struct BrowserNavigationEvent {
    let phase: BrowserNavigationPhase
    let url: URL?
    let title: String?
    let progress: Double
    let isLoading: Bool
}

struct BrowserSnapshotConfiguration {
    let rect: CGRect?
    let afterScreenUpdates: Bool

    static let full = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
}

/// Who asked for a video to float. Automatic floats return inline when the user comes back
/// to the tab; manual floats stay until the user returns them.
enum BrowserFloatingVideoOrigin: String {
    case automatic
    case manual
}

/// A `<video>` element on the page, measured in CSS pixels by the floating video script.
struct BrowserVideoCandidate: Decodable, Equatable {
    let id: Int
    let width: Double
    let height: Double
    /// Share of the element's area inside the viewport, from 0 to 1. Zero when hidden by CSS.
    let visibleFraction: Double
    let isPlaying: Bool
    /// True when the element is muted or its volume is zero.
    let isMuted: Bool
    let isFloating: Bool
    let isFloatingAutomatically: Bool
    let supportsFloating: Bool
}
