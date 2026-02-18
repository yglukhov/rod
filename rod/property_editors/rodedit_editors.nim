import std/strutils
import nimx/[view, text_field, matrixes, image, button,
    property_visitor, numeric_text_field, layout,
    slider, animation, context, view_event_handling, event,
    font
]
import nimx/property_editors/[standard_editors, propedit_registry] #used
import ../component/[nine_part_sprite ]
import ../[node, viewport, quaternion, rod_types]
import variant

template toStr(v: SomeFloat, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeFloat) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = type(t)(v.parseInt())

type NodeAnchorView = ref object of View
  pX: float
  pY: float
  pSize: Size
  onChanged: proc(p: Point) {.gcsafe.}

proc ppx(v: NodeAnchorView): float = v.pX / v.pSize.width
proc ppy(v: NodeAnchorView): float = v.pY / v.pSize.height

method draw(v: NodeAnchorView, r: Rect) =
  let dotSize = 10.0

  let c = currentContext()
  c.fillColor = v.backgroundColor
  c.strokeColor = blackColor()
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
  discard procCall v.View.onTouchEv(e)

  echo "nodeAnchor setter ", e.localPosition

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
    v.pX = px * v.pSize.width
    v.pY = py * v.pSize.height
    v.onChanged(newPoint(v.pX, v.pY))
  result = true

proc newNodeAnchorAUXPropertyView(setter: proc(s: NodeAnchorAUX) {.gcsafe.}, getter: proc(): NodeAnchorAUX {.gcsafe.}): PropertyEditorView =
  let boxSize = 50.0
  proc update() {.gcsafe.}
  let n = getter().node
  let bbox = n.nodeBounds()
  var minP = bbox.minPoint
  var maxP = bbox.maxPoint

  result = PropertyEditorView.new()
  result.makeLayout:
    - NodeAnchorView as v:
      x == super.x + 5
      y == super.y + 5
      width == boxSize
      height == boxSize
      bottom == super - 5
      pX: n.anchor.x
      pY: n.anchor.y
      pSize: newSize(maxP.x - minP.x, maxP.y - minP.y)

  if v.pSize.width > 0 and v.pSize.height > 0:
    v.onChanged = proc(p: Point) {.gcsafe.} =
      getter().node.anchor = newVector3(p.x, p.y)
      update()

  proc update() {.gcsafe.} =
    discard

registerPropertyEditor(newNodeAnchorAUXPropertyView)

type NinePartView = ref object of View
  segments: Vector4
  image: Image
  size: Size
  segmentsHighlight: array[4, bool]
  scale: float
  mOnAction: proc() {.gcsafe.}
  prevTouch: Point
  editedSegment: int

proc onAction(v: NinePartView, cb: proc() {.gcsafe.} ) =
  v.mOnAction = proc() =
    if not cb.isNil:
      cb()

method init(v: NinePartView) =
  procCall v.View.init()
  v.trackMouseOver(true)

proc imageRect(v: NinePartView): Rect =
  if v.image.isNil: return
  result = newRect(zeroPoint, newSize(v.image.size.width * v.scale, v.image.size.height * v.scale))

method draw(v: NinePartView, r: Rect) =
  procCall v.View.draw(r)
  if v.image.isNil: return

  let c = currentContext()
  let font = systemFont()

  var maxSize = max(v.image.size.width, v.image.size.height)
  let imgArea = newRect(0, 0, r.width, r.height - 20)
  v.scale = imgArea.width / maxSize
  var dr = v.imageRect()
  c.drawImage(v.image, dr)

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

proc newNinePartViewEditor(setter: proc(s: NinePartSegmentsAUX) {.gcsafe.}, getter: proc(): NinePartSegmentsAUX {.gcsafe.}): PropertyEditorView =
  let n = getter()
  proc complexSetter() {.gcsafe.}
  proc updateTfs(v: Vector4) {.gcsafe.}
  var r = new (PropertyEditorView)
  r.makeLayout:
    - NinePartView as ninepart:
      top == super
      leading == super
      # trailing == super
      height == 170
      width == 170
      size: n.size
      segments: n.segments
      image: n.image
      onAction:
        setter(NinePartSegmentsAUX(segments: ninepart.segments, image: ninepart.image, size: ninepart.size))
        updateTfs(ninepart.segments)

    - NumericTextField as xComp:
      top == prev.bottom
      bottom == super
      leading == super
      width == super * 0.25
      height == editorRowHeight
      name: "#0"
      font: editorFont()
      text: toStr(ninepart.segments[0], xComp.precision)
      onAction:
        complexSetter()

    - NumericTextField as yComp:
      top == prev
      width == prev
      leading == prev.trailing
      height == editorRowHeight
      name: "#1"
      font: editorFont()
      text: toStr(ninepart.segments[1], xComp.precision)
      onAction:
        complexSetter()

    - NumericTextField as zComp:
      top == prev
      width == prev
      leading == prev.trailing
      height == editorRowHeight
      name: "#2"
      font: editorFont()
      text: toStr(ninepart.segments[2], xComp.precision)
      onAction:
        complexSetter()

    - NumericTextField as wComp:
      top == prev
      width == prev
      leading == prev.trailing
      height == editorRowHeight
      name: "#3"
      font: editorFont()
      text: toStr(ninepart.segments[3], xComp.precision)
      onAction:
        complexSetter()

  result = r

  proc complexSetter() {.gcsafe.} =
    try:
      var v: Vector4
      xComp.text.fromStr(v.x)
      yComp.text.fromStr(v.y)
      zComp.text.fromStr(v.z)
      wComp.text.fromStr(v.w)
      ninepart.segments = v
      setter(NinePartSegmentsAUX(segments: ninepart.segments, image: ninepart.image, size: ninepart.size))
    except ValueError:
      discard

  proc updateTfs(v: Vector4) {.gcsafe.} =
    xComp.text = toStr(v.x, xComp.precision)
    yComp.text = toStr(v.y, yComp.precision)
    zComp.text = toStr(v.z, zComp.precision)
    wComp.text = toStr(v.w, wComp.precision)

registerPropertyEditor(newNinePartViewEditor)
