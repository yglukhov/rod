import std/[json]
import nimx / [ window, layout, animation ]
import ../../ rod / [ rod_types, node, message_queue ]
import ./[editor_view_types, editor_server]
import ./[editor_view, editor_project_settings]

type
  Editor* = ref object of EditorCommandQueue
    # messageQueue*: EditorMessageQueue
    mode*: EditorMode
    workspace: EditorView
    mCurrentComposition: CompositionDocument
    updateAnimation: Animation
    apiHandler: EditorServer
    currentProject: EditorProject
    # remoteEditorAPI: EditorAPI

template rootNode(e: Editor): Node = e.mCurrentComposition.rootNode
template composition(e: Editor): CompositionDocument = e.mCurrentComposition
proc `composition=`(e: Editor, c: CompositionDocument) =
  if e.composition != c:
    e.mCurrentComposition = c
    e.apiHandler.setRootNodeLocally(e.rootNode) #todo: think about this
    e.workspace.setCurrentComposition(c)

method post*(e: Editor, id: MessageId, msg: EditorMessage) =
  if id == EditorMessageNodeSelectionChanged.toEditorMessageId:
    sandbox:
      var changed = cast[EditorMessageNodeSelectionChanged](msg)
      echo "select ", changed.path
      e.workspace.setInspectedNode(e.rootNode.nodeAtPath(changed.path))
  else:
    e.apiHandler.consumeLocally(id, msg)

proc initFakeComposition(): CompositionDocument =
  result = new(CompositionDocument)
  result.rootNode = newNode("123")
  result.path = "123.s"

  var root = newNode("root")
  for i in 0 .. 10:
    var n = newNode($i)
    root.addChild(n)

    for q in 0 ..< i:
      var ch = newNode($q)
      n.addChild(ch)
      n = ch

  result.rootNode.addChild(root)

proc update(e: Editor) = discard

proc createEditor*(w: Window, proj: EditorProject): Editor =
  result.new()

  w.makeLayout:
    title: "Project " & proj.name
    - EditorView as editView:
      origin == super
      size == super

  result.currentProject = proj
  result.workspace = editView
  result.workspace.setEditorCommandsHandler(result)
  result.updateAnimation = newAnimation()
  let editor = result
  result.updateAnimation.onAnimate = proc(p: float) =
    editor.update()
  w.window.addAnimation(result.updateAnimation)

  result.apiHandler = EditorServer.new()
  result.apiHandler.setEventListner do(ev: EditorApiEvent) {.gcsafe.}:
    editor.workspace.onEditorEvent(ev)
  result.composition = initFakeComposition()