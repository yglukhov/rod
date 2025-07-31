import rod / [ rod_types ]
import animation / animation_editor_types

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

type
   CompositionDocument* = ref object
        path*: string
        rootNode*: Node
        selectedNode*: Node
        # owner*: EditorTabView

        animations*: seq[EditedAnimation]
        currentAnimation*: EditedAnimation