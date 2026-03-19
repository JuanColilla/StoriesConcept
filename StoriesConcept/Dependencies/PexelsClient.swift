import ComposableArchitecture
import Foundation
import os

// MARK: - Client Interface

@DependencyClient
struct PexelsClient: Sendable {
    var fetchCuratedPhotos: @Sendable (_ page: Int, _ perPage: Int) async throws -> [PexelsPhoto]
    var fetchPopularVideos: @Sendable (_ page: Int, _ perPage: Int) async throws -> [PexelsVideo]
    var fetchAvatarPhotos: @Sendable (_ page: Int, _ perPage: Int) async throws -> [PexelsPhoto]
    var downloadData: @Sendable (_ url: URL) async throws -> Data

    // Pure function — no dependency injection needed
    static func selectVideoFile(from files: [PexelsVideoFile]) -> PexelsVideoFile? {
        let hdFile = files.first { file in
            file.quality == "hd" && file.fileType == "video/mp4" && (file.height ?? 0) <= 1080
        }
        if let hdFile { return hdFile }

        let mp4Files = files
            .filter { $0.fileType == "video/mp4" && ($0.height ?? 0) <= 1080 }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let best = mp4Files.first { return best }

        return files.first
    }
}

// MARK: - Error

enum PexelsError: Error, LocalizedError, Equatable {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to fetch data from Pexels"
        }
    }
}

// MARK: - Live Implementation

extension PexelsClient: DependencyKey {
    static let liveValue: PexelsClient = {
        let apiKey = Constants.pexelsAPIKey
        let baseURL = Constants.pexelsBaseURL
        let session = URLSession.shared

        @Sendable
        func authorizedRequest<T: Decodable>(url: URL) async throws -> T {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                throw PexelsError.requestFailed
            }

            return try JSONDecoder().decode(T.self, from: data)
        }

        return PexelsClient(
            fetchCuratedPhotos: { page, perPage in
                let url = URL(string: "\(baseURL)/v1/curated?page=\(page)&per_page=\(perPage)")!
                Logger.api.debug("Fetching curated photos — page: \(page, privacy: .public), perPage: \(perPage, privacy: .public)")
                let response: PexelsPhotoResponse = try await authorizedRequest(url: url)
                Logger.api.debug("Fetched \(response.photos.count, privacy: .public) curated photos")
                return response.photos
            },
            fetchPopularVideos: { page, perPage in
                let url = URL(string: "\(baseURL)/videos/popular?page=\(page)&per_page=\(perPage)")!
                Logger.api.debug("Fetching popular videos — page: \(page, privacy: .public), perPage: \(perPage, privacy: .public)")
                let response: PexelsVideoResponse = try await authorizedRequest(url: url)
                Logger.api.debug("Fetched \(response.videos.count, privacy: .public) popular videos")
                return response.videos
            },
            fetchAvatarPhotos: { page, perPage in
                let url = URL(string: "\(baseURL)/v1/search?query=portrait+face&page=\(page)&per_page=\(perPage)")!
                Logger.api.debug("Fetching avatar photos — page: \(page, privacy: .public), perPage: \(perPage, privacy: .public)")
                let response: PexelsPhotoResponse = try await authorizedRequest(url: url)
                Logger.api.debug("Fetched \(response.photos.count, privacy: .public) avatar photos")
                return response.photos
            },
            downloadData: { url in
                Logger.api.debug("Downloading data from: \(url.absoluteString, privacy: .public)")
                let (data, _) = try await session.data(from: url)
                Logger.api.debug("Downloaded \(data.count, privacy: .public) bytes")
                return data
            }
        )
    }()

    static let previewValue = PexelsClient(
        fetchCuratedPhotos: { _, _ in
            [
                PexelsPhoto(
                    id: 1,
                    width: 1080,
                    height: 1920,
                    photographer: "Preview User",
                    avgColor: "#AABBCC",
                    src: PexelsSrc(
                        original: "https://example.com/photo.jpg",
                        large2x: "https://example.com/photo.jpg",
                        large: "https://example.com/photo.jpg",
                        medium: "https://example.com/photo.jpg",
                        small: "https://example.com/photo.jpg",
                        portrait: "https://example.com/photo.jpg",
                        landscape: "https://example.com/photo.jpg",
                        tiny: "https://example.com/photo.jpg"
                    )
                )
            ]
        },
        fetchPopularVideos: { _, _ in
            [
                PexelsVideo(
                    id: 1,
                    width: 1920,
                    height: 1080,
                    duration: 15,
                    image: "https://example.com/thumb.jpg",
                    videoFiles: [
                        PexelsVideoFile(
                            id: 1,
                            quality: "hd",
                            fileType: "video/mp4",
                            width: 1920,
                            height: 1080,
                            fps: 30.0,
                            link: "https://example.com/video.mp4"
                        )
                    ]
                )
            ]
        },
        fetchAvatarPhotos: { _, _ in
            [
                PexelsPhoto(
                    id: 2,
                    width: 400,
                    height: 400,
                    photographer: "Avatar User",
                    avgColor: "#112233",
                    src: PexelsSrc(
                        original: "https://example.com/avatar.jpg",
                        large2x: "https://example.com/avatar.jpg",
                        large: "https://example.com/avatar.jpg",
                        medium: "https://example.com/avatar.jpg",
                        small: "https://example.com/avatar.jpg",
                        portrait: "https://example.com/avatar.jpg",
                        landscape: "https://example.com/avatar.jpg",
                        tiny: "https://example.com/avatar.jpg"
                    )
                )
            ]
        },
        downloadData: { _ in
            Data()
        }
    )
}

// MARK: - Dependency Registration

extension DependencyValues {
    var pexelsClient: PexelsClient {
        get { self[PexelsClient.self] }
        set { self[PexelsClient.self] = newValue }
    }
}
