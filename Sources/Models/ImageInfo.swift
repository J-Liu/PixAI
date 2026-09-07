import Foundation

struct ImageInfo: Identifiable, Equatable, Codable {
    let id: String  // url.absoluteString
    let url: URL
    var filename: String { url.lastPathComponent }
    var fileSize: Int64?

    static func == (lhs: ImageInfo, rhs: ImageInfo) -> Bool {
        lhs.id == rhs.id
    }
}
