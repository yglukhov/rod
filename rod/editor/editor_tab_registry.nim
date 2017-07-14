import typetraits
import nimx.types, nimx.view

type
   EditViewEntry* = tuple
      name: string
      create: proc(): View

var gRegisteredViews = newSeq[EditViewEntry]()

template registerEditorTab*(tn: string, t: typedesc)=
    registerClass(t)
    var evr: EditViewEntry
    evr.name = tn
    let typename = typetraits.name(t)
    evr.create = proc():View=
        result = newObjectOfClass(typename).View
        result.name = evr.name

    gRegisteredViews.add(evr)

iterator registeredEditorTabs*():EditViewEntry=
    for rt in gRegisteredViews:
        yield rt
