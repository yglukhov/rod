import typetraits
import nimx / [ types, view ]

const RodInternalTab* = "RodInternalTab"

type
   EditViewEntry* = tuple
      name: string
      create: proc(): View

var gRegisteredViews = newSeq[EditViewEntry]()

proc registerEditorTabAux(tn: string, t: typedesc) =
    var evr: EditViewEntry
    evr.name = tn
    let typename = typetraits.name(t)
    evr.create = proc(): View =
        result = newObjectOfClass(typename).View
        result.name = evr.name

    gRegisteredViews.add(evr)

template registerEditorTab*(tn: string, t: typedesc) =
    doAssert(tn.len > 0, "Tab must have the name")
    registerClass(t)
    registerEditorTabAux(tn, t)

iterator registeredEditorTabs*():EditViewEntry=
    for rt in gRegisteredViews:
        yield rt

proc getRegisteredEditorTab*(name: string): EditViewEntry=
    for rt in registeredEditorTabs():
        echo "find ", name, " != ", rt.name
        if rt.name == name:
            echo "find tab ", name
            return rt
