import nimx / [ types, matrixes, context, view ]
import rod / [ rod_types, node, component, viewport ]
import rod / tools / debug_draw
import editor_component
import math

type GridComponent* = ref object of Component
  gridSize: Size

method componentNodeWasAddedToSceneView(c: GridComponent) =
  c.gridSize = newSize(100, 100)

method onDrawGizmo*(c: GridComponent) =
  let scene = c.node.sceneView
  let ss = scene.bounds
  let p0 = scene.screenToWorldPoint(newVector3())
  let p1 = scene.screenToWorldPoint(newVector3(ss.width, ss.height))    

  let ctx = currentContext()

  template drawGrid(r: Rect, s: Size, color: Color) =
    var gr = r
    gr.origin.x = gr.x - (s.width + (gr.x mod s.width))
    gr.origin.y = gr.y - (s.height + (gr.y mod s.height))
    gr.size.width += s.width * 2
    gr.size.height += s.height * 2
    ctx.strokeColor = color
    
    DDdrawGrid(gr, s)

  var gr = newRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y)
  
  #todo: remove this draw
  DDdrawCircle(newVector3(), 1) 

  drawGrid(gr, c.gridSize, newColor(0.0, 0.0, 0.0, 0.1))
  drawGrid(gr, newSize(c.gridSize.width * 5, c.gridSize.height * 5), newColor(0.0, 0.0, 0.0, 0.3))
  
registerComponent(GridComponent, "Editor")
