import std/[json]
import nimx / [ window, layout, animation ]
import ../../ rod / [ rod_types, node, message_queue ]
import ./[editor_types, editor_server]
import ./[editor_view, editor_project_settings]

type
  Editor* = ref object of EditorCommandQueue
    # messageQueue*: EditorMessageQueue
    mode*: EditorMode
    workspace: EditorView
    mCurrentComposition: CompositionDocument
    updateAnimation: Animation
    apiHandler: EditorAPI
    # remoteEditorAPI: EditorAPI

template composition(e: Editor): CompositionDocument = e.mCurrentComposition
proc `composition=`(e: Editor, c: CompositionDocument) =
  if e.composition != c:
    e.mCurrentComposition = c
    e.workspace.setCurrentComposition(c)

method post*(e: EditorCommandQueue, cmd: EditorCommand, msg: EditorMessage) =
  # e.apiHandler.
  discard

proc initFakeComposition(): CompositionDocument =
  result = new(CompositionDocument)
  result.rootNode = newNode("123")
  result.path = "123.s"

  var root = newNode("root")
  for i in 0..10:
    var n = newNode($i)
    root.addChild(n)

    for q in 0..< i:
      var ch = newNode($q)
      n.addChild(ch)
      n = ch

  result.rootNode.addChild(root)

proc update(e: Editor) = discard
  # e.apiHandler.update()
  # for id, msg in e.messageQueue.popChunk(chunk = 50):
  #   if id == $EditorCommand.node:
  #     let addNode = cast[EditorMessageAddNode](msg)
  #     echo addNode.parentPath, " nodename ", addNode.nodeName, " serialized ", %msg, " 2 ", %addNode
  #   else:
  #     echo "received msg ", cast[int](id)

proc createEditor*(w: Window, proj: EditorProject): Editor =
  result.new()
  # result.messageQueue.new()
  # result.mode = EditorMode.edit

  w.makeLayout:
    title: "Project " & proj.name
    - EditorView as editView:
      origin == super
      size == super

  result.workspace = editView
  result.workspace.setEditorCommandsHandler(result)

  result.composition = initFakeComposition()
  result.updateAnimation = newAnimation()
  let editor = result
  result.updateAnimation.onAnimate = proc(p: float) =
    editor.update()
  w.window.addAnimation(result.updateAnimation)

  result.apiHandler = EditorServer.new()