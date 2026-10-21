import Foundation

/// Подборка, которую пользователь собрал сам.
struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var itemIDs: [UUID]
}

/// Ссылка на набор обоев: всё, только видео, встроенная тема или своя подборка.
enum PlaylistRef: Codable, Hashable {
    case all
    case videos
    case collection(ShaderCollection)
    case custom(UUID)
}
