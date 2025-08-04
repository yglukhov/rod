import ../[ rod_types, message_queue ]
import ./[editor_api, editor_composition]

type EditorServer* = ref object of EditorAPI
    messageQueue*: EditorMessageQueue

proc update*(e: EditorServer) =
    for id, msg in e.messageQueue.popChunk(chunk = 50):
        discard

method move*(api: EditorAPI, queue: EditorMessageQueue) = discard

# method createComposition*(e: EditorServer): CompositionDocument  = discard
# method loadComposition*(e:EditorServer, path: string)  = discard
# method saveComposition*(e: EditorServer, c: CompositionDocument)  = discard
# method closeComposition*(e: EditorServer, c:CompositionDocument)  = discard
# method addChildNode*(e: EditorServer, parent: Node, n: Node)  = discard
# method removeNode*(e: EditorServer, n: Node)  = discard
