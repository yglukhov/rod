import std/[hashes, strutils]
import ../../ rod / [ rod_types, message_queue ]
import ./[ editor_composition, editor_api_msg, editor_api_events ]
export message_queue, editor_api_msg, editor_api_events

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
  not defined(emscripten) and not defined(js)

const enableEditorSandbox = true

when loadingAndSavingAvailable:
  import os_files/dialog
  import os

type
  EditorMessageQueue* = MessageQueue[EditorMessage]
  EditorApiListner* = proc(event: EditorApiEvent) {.gcsafe.}
  EditorAPI* = ref object of RootObj
  EditorCommandQueue* = ref object of RootObj

method consumeLocally*(api: EditorAPI, id: MessageId, msg: EditorMessage) {.base, gcsafe.} = discard
method setRootNodeLocally*(api: EditorAPI, node: Node) {.base, gcsafe.} = discard
method setEventListner*(api: EditorApi, listner: EditorApiListner) {.base, gcsafe.} = discard

proc toEditorMessageId*[Msg](msg: typedesc[Msg]): MessageId {.compileTime.} =
  result = ($Msg).toMessageId

method post*(e: EditorCommandQueue, id: MessageId, msg: EditorMessage) {.base, gcsafe.} = discard
proc post*[T](e: EditorCommandQueue, msg: T) = e.post(T.toEditorMessageId, msg)

template sandboxed(body: untyped, instInfo: tuple[filename: string, line: int, column: int]): untyped =
  try:
    body
  except Exception as e:
    echo instInfo.filename, " at line:", instInfo.line, " EditorServer got error ", e.msg, "\n", getStackTrace(e)

template sandbox*(body: untyped): untyped =
  when enableEditorSandbox:
    let instInfo = instantiationInfo()
    sandboxed(body, instInfo)
  else:
    body

proc nodeAtPath*(rootNode: Node, path: seq[int]): Node =
  result = rootNode
  for i in path:
    result = result.children[i]
    echo " i, ", i, " result ", result.name

when loadingAndSavingAvailable:
  proc relativeUrl*(url: string, base: string): string =
    result = url
    result.removePrefix("file://")
    result = relativePath(result, base).replace("\\", "/")
else:
  proc relativeUrl*(url: string, base: string): string = url

# Pasteboard
const rodPbComposition* = "rod.composition"
# const rodPbSprite* = "rod.sprite"
const rodPbSprite* = "nimx.pb.image"
const rodPbFiles* = "rod.files"
const NodePboardKind* = "io.github.yglukhov.rod.node"
const BezierPboardKind* = "io.github.yglukhov.rod.bezier"

# Editor's nodes
const EditorRootNodeName* = "[EditorRoot]"