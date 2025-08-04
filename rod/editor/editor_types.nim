import nimx / view
import ../../ rod / [ rod_types, message_queue ]
import ./animation / animation_editor_types
import ./[editor_api, editor_composition]
export editor_api, editor_composition, message_queue

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

type
  EditorMode* {.pure.} = enum
    edit
    animation
    play

  EditorTabView* = ref object of View
    composition*: CompositionDocument
    commandsQueue*: EditorCommandQueue

  EditorTabPanel* = ref object of View

method onCompositionChanged*(v: EditorTabView, c: CompositionDocument) {.base, gcsafe.} =
  v.composition = c

method tabs*(v: EditorTabPanel): seq[EditorTabView] {.base, gcsafe.} = @[]
