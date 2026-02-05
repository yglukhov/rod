import ../../ rod / rod_types
import ./animation / editor_animation_types

type CompositionDocument* = ref object
  path*: string
  rootNode*: Node
  selectedNode*: Node
  animations*: seq[EditedAnimation]
  currentAnimation*: EditedAnimation
