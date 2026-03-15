import Foundation

enum Constants {
    static let pexelsAPIKey = "r7EbWKvE0Y1PW8N91otVyz5nyT6UK3JPtrqirOncGapeCiSJ18sNp73z"
    static let pexelsBaseURL = "https://api.pexels.com"

    static let photoAutoAdvanceDuration: TimeInterval = 15
    static let maxVideoDuration: TimeInterval = 45
    static let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours
    static let usersPerBlock = 10
    static let minStoriesPerUser = 1
    static let maxStoriesPerUser = 10
    static let dragMinDistance: CGFloat = 20

    static let namePool: [String] = [
        // English
        "emma", "jake", "sophie", "oliver", "mia", "noah", "lily", "max",
        "hannah", "ryan", "zoe", "tyler", "grace", "mason", "aria", "logan",
        "ella", "connor",
        // Spanish
        "carlos", "sofia", "alejandro", "valentina", "diego", "camila", "mateo",
        "isabella", "santiago", "paula", "daniel", "lucia", "andres", "elena",
        "pablo", "maria", "javier", "carmen", "rafael", "alba",
        // French
        "hugo", "manon", "louis", "lea", "jules", "arthur", "lucas", "camille",
        "gabriel", "louise", "raphael", "alice", "theo", "ines", "leon", "jade",
        "antoine", "margot"
    ]
}
