import nimx/[view, text_field, matrixes, image, button,
    linear_layout, property_visitor, numeric_text_field,
    slider, animation, context, view_event_handling, event,
    font
]
import rod/component/[rti, nine_part_sprite ]
import rod/property_editors/propedit_registry
import nimx/property_editors/standard_editors #used
import rod/[node, viewport, quaternion, rod_types]
import variant

type NodeAnchorView = ref object of View
  pX: float
  pY: float
  size: Size
  onChanged: proc(p: Point)

proc ppx(v: NodeAnchorView): float = v.pX / v.size.width
proc ppy(v: NodeAnchorView): float = v.pY / v.size.height

method draw(v: NodeAnchorView, r: Rect) =
  let dotSize = 10.0

  let c = currentContext()
  c.fillColor = clearColor()
  c.strokeWidth = 3
  c.drawRect(r)

  c.strokeWidth = 1
  c.fillColor = blackColor()
  c.drawLine(newPoint(r.x + r.width * 0.5, r.y), newPoint(r.x + r.width * 0.5, r.y + r.height))
  c.drawLine(newPoint(r.x , r.y + r.height * 0.5), newPoint(r.x + r.width, r.y + r.height * 0.5))

  c.fillColor = newColor(1.0, 0.2, 0.4, 1.0)
  c.strokeWidth = 0
  c.drawEllipseInRect(newRect(v.ppx * r.width - dotSize * 0.5, v.ppy * r.height - dotSize * 0.5, dotSize, dotSize))

method onTouchEv*(v: NodeAnchorView, e: var Event): bool =
  var px = (e.localPosition.x / v.bounds.size.width)
  var py = (e.localPosition.y / v.bounds.size.height)

  template algn(p1: float) =
    if p1 < 0.25:
      p1 = 0.0
    elif p1 > 0.25 and p1 < 0.75:
      p1 = 0.5
    else:
      p1 = 1.0

  px.algn()
  py.algn()

  if (v.ppx != px or v.ppy != py) and not v.onChanged.isNil:
    v.pX = px * v.size.width
    v.pY = py * v.size.height
    v.onChanged(newPoint(v.pX, v.pY))
  result = true

proc newNodeAnchorAUXPropertyView(setter: proc(s: NodeAnchorAUX), getter: proc(): NodeAnchorAUX): PropertyEditorView =
  let boxSize = 100.0
  result = PropertyEditorView.new(newRect(0, 0, 208, boxSize + 10))
  let n = getter().node
  var minP = newVector3(high(float), high(float))
  var maxP = newVector3(low(float), low(float))
  n.nodeBounds2d(minP, maxP)

  var v = NodeAnchorView.new(newRect(0, 5, boxSize, boxSize))
  v.size = newSize(maxP.x - minP.x, maxP.y - minP.y)
  v.pX = n.anchor.x
  v.pY = n.anchor.y
  if v.size.width > 0 and v.size.height > 0:
    v.onChanged = proc(p: Point) =
      n.anchor = newVector3(p.x, p.y)
  # echo "size ", v.size, " x ", v.pX, " y ", v.pY
  result.addSubview(v)

registerPropertyEditor(newNodeAnchorAUXPropertyView)

type NinePartView = ref object of View
  segments: Vector4
  image: Image
  size: Size
  segmentsHighlight: array[4, bool]
  scale: float
  mOnAction: proc()
  prevTouch: Point
  editedSegment: int

proc onAction(v: NinePartView, cb: proc()) =
  v.mOnAction = cb

method init(v: NinePartView, r: Rect) =
  procCall v.View.init(r)
  v.trackMouseOver(true)

proc imageRect(v: NinePartView): Rect =
  if v.image.isNil: return
  result = newRect(zeroPoint, newSize(v.image.size.width * v.scale, v.image.size.height * v.scale))

method draw(v: NinePartView, r: Rect) =
  if v.image.isNil: return

  let c = currentContext()
  let font = systemFont()

  var maxSize = max(v.image.size.width, v.image.size.height)
  let imgArea = newRect(0, 0, r.width, r.height - 20)
  v.scale = imgArea.width / maxSize
  var dr = v.imageRect()
  c.drawImage(v.image, dr)

  # c.drawText(font, newPoint(0, 0), "left")
  # c.drawText(font, newPoint(50, 0), "right")
  # c.drawText(font, newPoint(100, 0), "top")
  # c.drawText(font, newPoint(150, 0), "bottom")

  c.strokeWidth = 3

  const lbls = ["left", "right", "top", "bottom"]
  template drawSegment(i: int, body: untyped) =
    let pc = c.strokeColor
    if v.segmentsHighlight[i]:
      c.strokeColor = newColor(1.0, 0.4, 0.2, 1.0)
    body
    if v.segmentsHighlight[i]:
      c.drawText(font, newPoint(0, r.height - 20), lbls[i] & " " & $v.segments[i])
    c.strokeColor = pc

  #left
  drawSegment 0:
    c.drawLine(newPoint(v.segments.x * v.scale, 0), newPoint(v.segments.x * v.scale, dr.height))

  #right
  drawSegment 1:
    c.drawLine(newPoint(dr.width - v.segments.y * v.scale, 0), newPoint(dr.width - v.segments.y * v.scale, dr.height))

  #top
  drawSegment 2:
    c.drawLine(newPoint(0, v.segments.z * v.scale), newPoint(r.width, v.segments.z * v.scale))

  #bottom
  drawSegment 3:
    c.drawLine(newPoint(0, dr.height - v.segments.w * v.scale), newPoint(r.width, dr.height - v.segments.w * v.scale))

  c.strokeWidth = 1


proc segmentAt(v: NinePartView, p: Point): int =
  var dr = v.imageRect()
  const margin = 10.0

  result = -1
  template check(i: int, r: Rect) =
    if r.contains p:
      return i

  check 0, newRect(newPoint(v.segments.x * v.scale - margin, 0), newSize(margin * 2, dr.height))
  check 1, newRect(newPoint(dr.width - v.segments.y * v.scale - margin, 0), newSize(margin * 2, dr.height))
  check 2, newRect(newPoint(0, v.segments.z * v.scale - margin), newSize(dr.width, margin * 2))
  check 3, newRect(newPoint(0, dr.height - v.segments.w * v.scale - margin), newSize(dr.width, margin * 2))

method onTouchEv*(v: NinePartView, e: var Event): bool =
  if e.buttonState == bsDown:
    v.prevTouch = e.localPosition
    v.editedSegment = v.segmentAt(e.localPosition)
    return true
  else:
    var dr = v.imageRect()
    let i = v.editedSegment
    case i:
    of 0: #left
      v.segments[i] = e.localPosition.x / v.scale
    of 1: #right
      v.segments[i] = (dr.width - e.localPosition.x) / v.scale
    of 2: #top
      v.segments[i] = e.localPosition.y / v.scale
    of 3: #bottom
      v.segments[i] = (dr.height - e.localPosition.y) / v.scale
    else:
      discard

    if not v.mOnAction.isNil:
      v.mOnAction()
    result = true

proc clearHightlights(v: NinePartView) =
  for i in 0..3:
    v.segmentsHighlight[i] = false

method onMouseIn*(v: NinePartView, e: var Event) =
  v.clearHightlights()

method onMouseOver*(v: NinePartView, e: var Event) =
  v.clearHightlights()
  let i = v.segmentAt(e.localPosition)
  if i != -1:
    v.segmentsHighlight[i] = true

method onMouseOut*(v: NinePartView, e: var Event) =
  v.clearHightlights()

proc newNinePartViewEditor(setter: proc(s: NinePartSegmentsAUX), getter: proc(): NinePartSegmentsAUX): PropertyEditorView =
  let boxSize = 170.0
  let pv = PropertyEditorView.new(newRect(0,0,208, boxSize + 10))

  let n = getter()
  var v = NinePartView.new(newRect(0, 5, boxSize, boxSize))
  v.size = n.size
  v.segments = n.segments
  v.image = n.image
  v.onAction do():
    setter(NinePartSegmentsAUX(segments: v.segments, image: v.image, size: v.size))
    # if not pv.changeInspector.isNil:
    #     pv.changeInspector()
  pv.addSubview(v)
  result = pv

registerPropertyEditor(newNinePartViewEditor)
