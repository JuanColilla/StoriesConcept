import Foundation

@Observable
final class PexelsService {
    private let apiKey = Constants.pexelsAPIKey
    private let baseURL = Constants.pexelsBaseURL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    func fetchCuratedPhotos(page: Int, perPage: Int = 40) async throws -> PexelsPhotoResponse {
        let url = URL(string: "\(baseURL)/v1/curated?page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func fetchPopularVideos(page: Int, perPage: Int = 20) async throws -> PexelsVideoResponse {
        let url = URL(string: "\(baseURL)/videos/popular?page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func fetchAvatarPhotos(page: Int = 1, perPage: Int = 50) async throws -> PexelsPhotoResponse {
        let url = URL(string: "\(baseURL)/v1/search?query=portrait+face&page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func downloadData(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Video File Selection

    /// Select best video file: HD quality, mp4, height <= 1080p. Fallback to largest available.
    static func selectVideoFile(from files: [PexelsVideoFile]) -> PexelsVideoFile? {
        // Prefer HD mp4 <= 1080p
        let hdFile = files.first { file in
            file.quality == "hd" &&
            file.fileType == "video/mp4" &&
            (file.height ?? 0) <= 1080
        }
        if let hdFile { return hdFile }

        // Fallback: any mp4 <= 1080p sorted by height descending
        let mp4Files = files
            .filter { $0.fileType == "video/mp4" && ($0.height ?? 0) <= 1080 }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let best = mp4Files.first { return best }

        // Last resort: any file
        return files.first
    }

    // MARK: - Private

    private func request<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PexelsError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum PexelsError: Error, LocalizedError {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Failed to fetch data from Pexels"
        }
    }
}
