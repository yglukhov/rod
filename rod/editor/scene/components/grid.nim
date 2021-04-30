import nimx / [ types, matrixes, context, view, property_visitor ]
import rod / [ rod_types, node, component, viewport ]
import rod / tools / debug_draw
import editor_component
import math

type EditorGrid* = ref object of RenderComponent
  gridSize: Size
  offset: Point
  snap: bool

method componentNodeWasAddedToSceneView(c: EditorGrid) =
  c.gridSize = newSize(100, 100)

method onDrawGizmo*(c: EditorGrid) =
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

    DDdrawGrid(gr, s, c.offset)

  var gr = newRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y)
  drawGrid(gr, c.gridSize, newColor(0.0, 0.0, 0.0, 0.1))
  drawGrid(gr, newSize(c.gridSize.width * 5, c.gridSize.height * 5), newColor(0.0, 0.0, 0.0, 0.3))

method visitProperties*(c: EditorGrid, p: var PropertyVisitor) =
  p.visitProperty("size", c.gridSize)
  if c.gridSize.width < 1.0:
    c.gridSize.width = 1.0
  if c.gridSize.height < 1.0:
    c.gridSize.height = 1.0
  p.visitProperty("offset", c.offset)
  p.visitProperty("snap", c.snap)

proc snappingEnabled*(c: EditorGrid): bool = c.snap

proc snappedWorldPosition*(c: EditorGrid, p: Vector3): Vector3 =
  let x1 = splitDecimal((p.x - c.offset.x) / c.gridSize.width).floatPart
  let y1 = splitDecimal((p.y - c.offset.y) / c.gridSize.height).floatPart
  let xo = if x1 < 0.5: - c.gridSize.width * x1 else: (1 - x1) * c.gridSize.width
  let yo = if y1 < 0.5: - c.gridSize.height * y1 else: (1 - y1) * c.gridSize.height
  result = newVector3(p.x + xo, p.y + yo)

registerComponent(EditorGrid, "Editor")
