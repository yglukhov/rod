import nimx / [ types ]
import rod / [ rod_types, node, component, viewport ]
import rod / tools / debug_draw
import editor_component

type ViewportRect* = ref object of RenderComponent

method onDrawGizmo*(c: ViewportRect) =
  let scene = c.node.sceneView
  DDdrawRect(newRect(0, 0, scene.camera.viewportSize.width, scene.camera.viewportSize.height))

registerComponent(ViewportRect, "Editor")
