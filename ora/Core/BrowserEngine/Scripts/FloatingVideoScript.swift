import Foundation

/// Measures `<video>` elements and moves them in and out of picture in picture.
///
/// The script runs in the isolated world, so the page cannot call or replace
/// `window.__oraFloatingVideo`. It shares the DOM with the page, which is all it needs.
/// State lives only in page memory, so nothing survives a reload or reaches disk.
enum FloatingVideoScript {
    static let userScript = BrowserUserScript(
        name: "ora-floating-video",
        source: source,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true,
        world: .isolated
    )

    /// Resolves to a JSON array of `BrowserVideoCandidate` values.
    static let candidatesCall = """
    const api = window.__oraFloatingVideo;
    return api ? api.candidates() : '[]';
    """

    /// Arguments: `id` (number) and `origin` (`BrowserFloatingVideoOrigin` raw value).
    /// Resolves to `floating`, `missing`, `unsupported`, `unavailable`, or `failed:<ErrorName>`.
    static let enterCall = """
    const api = window.__oraFloatingVideo;
    return api ? await api.enter(id, origin) : 'unavailable';
    """

    /// Arguments: `minWidth`, `minHeight`, and `minVisibleFraction` (numbers).
    /// Picks the video to float when the user leaves the tab and floats it in the same call.
    /// Resolves to `floating`, `none`, `kept`, `unavailable`, or `failed:<ErrorName>`.
    static let enterAutomaticCall = """
    const api = window.__oraFloatingVideo;
    return api ? await api.enterAutomatic(minWidth, minHeight, minVisibleFraction) : 'unavailable';
    """

    /// Arguments: `automaticOnly` (boolean).
    /// Resolves to `inline`, `kept`, `unavailable`, or `failed:<ErrorName>`.
    static let exitCall = """
    const api = window.__oraFloatingVideo;
    return api ? await api.exit(automaticOnly) : 'unavailable';
    """

    private static let source = """
    (function () {
        if (window.__oraFloatingVideo) {
            return;
        }

        const PIP = 'picture-in-picture';
        const automaticVideos = new WeakSet();
        const ids = new WeakMap();
        let nextID = 1;

        function videos() {
            return Array.from(document.querySelectorAll('video'));
        }

        function identify(video) {
            if (!ids.has(video)) {
                ids.set(video, nextID++);
            }
            return ids.get(video);
        }

        function floatingVideo() {
            const element = document.pictureInPictureElement;
            if (element && element.tagName === 'VIDEO') {
                return element;
            }
            return videos().find((video) => video.webkitPresentationMode === PIP) || null;
        }

        function supportsFloating(video) {
            if (video.disablePictureInPicture || video.readyState < 1 || !video.videoWidth) {
                return false;
            }
            if (typeof video.webkitSupportsPresentationMode === 'function') {
                return video.webkitSupportsPresentationMode(PIP);
            }
            return typeof video.requestPictureInPicture === 'function' && document.pictureInPictureEnabled !== false;
        }

        function visibleFraction(video, rect) {
            const area = rect.width * rect.height;
            if (area <= 0) {
                return 0;
            }
            const style = window.getComputedStyle(video);
            if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) < 0.1) {
                return 0;
            }
            const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
            const visibleWidth = Math.max(0, Math.min(rect.right, viewportWidth) - Math.max(rect.left, 0));
            const visibleHeight = Math.max(0, Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0));
            return Math.min(1, (visibleWidth * visibleHeight) / area);
        }

        function describe(video, floating) {
            const rect = video.getBoundingClientRect();
            const isFloating = video === floating;
            return {
                id: identify(video),
                width: rect.width,
                height: rect.height,
                visibleFraction: visibleFraction(video, rect),
                isPlaying: !video.paused && !video.ended && video.readyState >= 2,
                isMuted: video.muted || video.volume === 0,
                isFloating: isFloating,
                isFloatingAutomatically: isFloating && automaticVideos.has(video),
                supportsFloating: supportsFloating(video)
            };
        }

        function errorResult(error) {
            return 'failed:' + ((error && error.name) || 'Error');
        }

        function forget(event) {
            const video = event.target;
            if (video && video.tagName === 'VIDEO' && video.webkitPresentationMode !== PIP) {
                automaticVideos.delete(video);
            }
        }

        document.addEventListener('leavepictureinpicture', forget, true);
        document.addEventListener('webkitpresentationmodechanged', forget, true);

        const api = {
            candidates() {
                const floating = floatingVideo();
                return JSON.stringify(videos().map((video) => describe(video, floating)));
            },

            // requestPictureInPicture() needs a user gesture. The app's call counts as one,
            // but only until the first await, so the request must happen synchronously here.
            async enter(id, origin) {
                const video = videos().find((element) => identify(element) === id);
                if (!video) {
                    return 'missing';
                }
                if (floatingVideo() === video) {
                    return 'floating';
                }

                if (origin === 'automatic') {
                    automaticVideos.add(video);
                } else {
                    automaticVideos.delete(video);
                }

                try {
                    if (typeof video.requestPictureInPicture === 'function') {
                        await video.requestPictureInPicture();
                    } else if (typeof video.webkitSetPresentationMode === 'function') {
                        video.webkitSetPresentationMode(PIP);
                    } else {
                        automaticVideos.delete(video);
                        return 'unsupported';
                    }
                    return 'floating';
                } catch (error) {
                    automaticVideos.delete(video);
                    return errorResult(error);
                }
            },

            // Mirrors FloatingVideoPolicy.automaticCandidate(from:rules:). The choice happens here,
            // in one call, so the request reaches the page before it learns the tab is hidden.
            enterAutomatic(minWidth, minHeight, minVisibleFraction) {
                const floating = floatingVideo();
                if (floating) {
                    return Promise.resolve('kept');
                }

                let best = null;
                let bestArea = 0;
                for (const video of videos()) {
                    const candidate = describe(video, floating);
                    const area = candidate.width * candidate.height * candidate.visibleFraction;
                    const eligible = candidate.supportsFloating &&
                        candidate.isPlaying &&
                        !candidate.isMuted &&
                        candidate.width >= minWidth &&
                        candidate.height >= minHeight &&
                        candidate.visibleFraction >= minVisibleFraction;
                    if (eligible && area > bestArea) {
                        best = candidate;
                        bestArea = area;
                    }
                }

                return best ? api.enter(best.id, 'automatic') : Promise.resolve('none');
            },

            async exit(automaticOnly) {
                const video = floatingVideo();
                if (!video) {
                    return 'inline';
                }
                if (automaticOnly && !automaticVideos.has(video)) {
                    return 'kept';
                }
                automaticVideos.delete(video);

                try {
                    if (document.pictureInPictureElement === video && document.exitPictureInPicture) {
                        await document.exitPictureInPicture();
                    } else if (typeof video.webkitSetPresentationMode === 'function') {
                        video.webkitSetPresentationMode('inline');
                    }
                    return 'inline';
                } catch (error) {
                    return errorResult(error);
                }
            }
        };

        Object.defineProperty(window, '__oraFloatingVideo', { value: Object.freeze(api) });
    })();
    """
}
