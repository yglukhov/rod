import typetraits
import nimx.types, nimx.matrixes, nimx.event
import nimx.view, nimx.table_view, nimx.scroll_view, nimx.button, nimx.text_field
import rod.node

type EditorTabAnchor* = enum
    etaLeft
    etaRight
    etaBottom
    etaCenter

type EditorTabView* = ref object of View
    rootNode*: Node

method editedNode*(v: EditorTabView, n: Node)=
    discard

method selectedNode*(v: EditorTabView, n: Node)=
    discard

method tabSize*(v: EditorTabView, bounds: Rect): Size=
    result = bounds.size

method tabAnchor*(v: EditorTabView): EditorTabAnchor =
    result = etaCenter

method onEditorTouchDown*(v: EditorTabView, e: var Event)=
    discard

method onSceneChanged*(v: EditorTabView)=
    discard

type EditViewEntry* = tuple
    name: string
    create: proc(): EditorTabView

var gRegisteredViews = newSeq[EditViewEntry]()

template registerEditorTad*(tn: string, t: typedesc)=
    registerClass(t)
    var evr: EditViewEntry
    evr.name = tn
    let typename = typetraits.name(t)
    evr.create = proc():EditorTabView=
        result = newObjectOfClass(typename).EditorTabView
        result.name = evr.name

    gRegisteredViews.add(evr)

iterator registeredEditorTabs*():EditViewEntry=
    for rt in gRegisteredViews:
        yield rt


