import CoreData
import Foundation
import MartenCore

func dashboardPinboardFetchRequest() -> NSFetchRequest<Pinboard> {
    let request = Pinboard.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    request.returnsObjectsAsFaults = false
    return request
}

func dashboardItemsFetchRequest(selectedPinboardID: UUID?) -> NSFetchRequest<ClipItem> {
    let request = ClipItem.fetchRequest()
    var predicates = [NSPredicate(format: "isTransient == NO")]

    if let selectedPinboardID {
        predicates.append(
            NSPredicate(format: "ANY pinboards.id == %@", selectedPinboardID as CVarArg)
        )
    }

    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

    if selectedPinboardID != nil {
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "modifiedAt", ascending: false),
        ]
    } else {
        request.sortDescriptors = [
            NSSortDescriptor(key: "modifiedAt", ascending: false)
        ]
    }

    request.returnsObjectsAsFaults = false
    request.relationshipKeyPathsForPrefetching = ["representations", "pinboards", "linkPreview"]

    return request
}

func searchAllItemsFetchRequest() -> NSFetchRequest<ClipItem> {
    let request = ClipItem.fetchRequest()
    request.predicate = NSPredicate(format: "isTransient == NO")
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
    request.fetchLimit = 500
    request.returnsObjectsAsFaults = false
    return request
}

