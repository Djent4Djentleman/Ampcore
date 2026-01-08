import CoreData

@objc(CDTrack)
public final class CDTrack: NSManagedObject {}

extension CDTrack {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTrack> {
        NSFetchRequest<CDTrack>(entityName: "CDTrack")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var artist: String?
    @NSManaged public var album: String?
    @NSManaged public var duration: Double
    @NSManaged public var addedAt: Date
    @NSManaged public var fileBookmark: Data
    @NSManaged public var fileExt: String
    @NSManaged public var isSupported: Bool
    @NSManaged public var lyrics: String?
    @NSManaged public var artworkData: Data?
    @NSManaged public var relativePath: String
}

@objc(CDPlaylist)
public final class CDPlaylist: NSManagedObject {}

extension CDPlaylist {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPlaylist> {
        NSFetchRequest<CDPlaylist>(entityName: "CDPlaylist")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var createdAt: Date
}
