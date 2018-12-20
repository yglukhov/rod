
import nimx / [view, button, editor/tab_view, linear_layout, popup_button,
    toolbar, notification_center, event ]
import rod / [node, viewport, editor/editor_project_settings]

export notification_center

const toolbarHeight* = 30

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

type
    EditorTabAnchor* = enum
        etaLeft
        etaRight
        etaBottom
        etaCenter

    EditorTabView* = ref object of View
        rootNode*: Node
        editor*: Editor
        composition*: CompositionDocument

    CompositionDocument* = ref object
        path*: string
        rootNode*: Node
        selectedNode*: Node
        owner*: EditorTabView

    Editor* = ref object
        sceneInput*: bool
        currentProject*: EditorProject
        mCurrentComposition*: CompositionDocument
        rootNode*: Node
        sceneView*: SceneView
        window*: Window
        mSelectedNode*: Node
        startFromGame*: bool
        workspaceView*: WorkspaceView
        cameraSelector*: PopupButton
        notifCenter*: NotificationCenter

    WorkspaceView* = ref object of View
        editor*: Editor
        toolbar*: Toolbar
        tabs*: seq[EditorTabView]
        tabViews*: seq[TabView]
        compositionEditors*: seq[EditorTabView]
        anchors*: array[4, TabView]
        horizontalLayout*: LinearLayout
        verticalLayout*: LinearLayout
        onKeyDown*: proc(e: var Event): bool

template selectedNode*(e: Editor): Node = e.mSelectedNode

method setEditedNode*(v: EditorTabView, n: Node) {.base.}=
    discard

method update*(v: EditorTabView) {.base.}= discard

method tabSize*(v: EditorTabView, bounds: Rect): Size {.base.}=
    result = bounds.size

method tabAnchor*(v: EditorTabView): EditorTabAnchor {.base.}=
    result = etaCenter

method onEditorTouchDown*(v: EditorTabView, e: var Event) {.base.}=
    discard

method onSceneChanged*(v: EditorTabView) {.base, deprecated.}=
    discard

method onCompositionChanged*(v: EditorTabView, comp: CompositionDocument) {.base.}=
    discard

# Notifications
const RodEditorNotif_onNodeLoad* = "RodEditorNotif_onNodeLoad"
const RodEditorNotif_onNodeSave* = "RodEditorNotif_onNodeSave"
const RodEditorNotif_onCompositionOpen* = "RodEditorNotif_onCompositionOpen"
const RodEditorNotif_onCompositionSave* = "RodEditorNotif_onCompositionSave"
const RodEditorNotif_onCompositionSaveAs* = "RodEditorNotif_onCompositionSaveAs"
const RodEditorNotif_onCompositionNew* = "RodEditorNotif_onCompositionNew"

# Pasteboard
const rodPbComposition* = "rod.composition"
const rodPbSprite* = "rod.sprite"
const rodPbFiles* = "rod.files"
const NodePboardKind* = "io.github.yglukhov.rod.node"

# Editor's nodes
const EditorCameraNodeName2D* = "[EditorCamera2D]"
const EditorCameraNodeName3D* = "[EditorCamera3D]"
const EditorRootNodeName* = "[EditorRoot]"

# Default open tabs
const defaultTabs* = ["Inspector", "Tree", "EditScene Settings"]

# Other
const EditorViewportSize* = newSize(1920.0, 1080.0)