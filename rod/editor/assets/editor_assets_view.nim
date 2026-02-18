import std/[ times ]
import kiwi
import nimx / [
  view, types, slider, layout, scroll_view, text_field, image, animation, drag_and_drop,
  layout_vars, context, view_event_handling, event, image_preview
  ]

import nimx/pasteboard/pasteboard_item
import ../[editor_view_types]
import ./[editor_assets_tree, path_node, editor_assets_thumbnail]

when not defined(android) and not defined(ios) and not defined(emscripten):
  import os_files/file_info

type
  EditorScrollContentView = ref object of View
      # mousevents
    assetsView: EditorAssetsView
    heightVar: Variable
    heightConst: Constraint
    thumbWidth: Variable
    thumbWidthConstr: Constraint
    thumbYOffset: Variable
    thumbYOffsetConstr: Constraint
    currentThumbSize: float
    currentFirstYOffset: float
    currentHeight: float
    offsetVar: Variable
    thumbLeading: Constraint
    thumbTop: Constraint
    thumbFirstLeading: Constraint
    thumbFirstTop: Constraint
    firstItemIndex: int
    itemsInARow: int
    dragStarted: bool
    selectionRect: Rect
    selectionOrigin: Point
    selectedItems*: seq[int]
    onItemsDragStart*: proc(item: seq[int]) {.gcsafe.}
    onItemRenamed*: proc(item:int) {.gcsafe.}
    onItemDeselected*: proc(item: int) {.gcsafe.}
    onItemSelected*: proc(item: int) {.gcsafe.}
    onItemDoubleClick*: proc(item: int) {.gcsafe.}
    onItemsDelete*: proc(item:seq[int]) {.gcsafe.}
    onBackspace*: proc() {.gcsafe.}

  EditorAssetsView* = ref object of View
    slider: Slider
    content: EditorScrollContentView
    thumbnails: seq[EditorThumbnailView]
    lineBreakers: seq[EditorThumbnailView]
    currentDir: PathNode
    pathLabel: Label

proc recalc(v: EditorAssetsView) {.gcsafe.}

method updateLayout*(v: EditorAssetsView) =
  procCall v.View.updateLayout()
  v.recalc()

proc moveToDirectory(v: EditorAssetsView, p: PathNode) =
  if p.isNil: return
  v.currentDir = p
  echo "EditorAssetsView curDit: ", p.path
  v.recalc()
  v.pathLabel.text = p.path
  v.content.selectedItems.setLen(0)

method init*(v: EditorAssetsView) =
  procCall v.View.init()

  v.makeLayout:
    # backgroundColor: uiBackground
    - EditorAssetsTreeView as tree:
      top == super
      leading == super
      width >= 200 @ WEAK
      bottom == super - 20
      onSelectionChanged do(p: PathNode):
        v.moveToDirectory(p)

    - ScrollView:
      top == super
      leading == prev.trailing
      trailing == super
      # backgroundColor: uiAccent
      - EditorScrollContentView as content:
        leading == super
        trailing == super
        assetsView: v
        currentFirstYOffset: -1
        currentThumbSize: -1
        currentHeight: -1

    - Label as curDir:
      # backgroundColor: uiBlue
      top == prev.bottom
      leading == super
      height == 20
      text: "Current path"

    - Slider as slider:
      # backgroundColor: uiHighlight
      top == prev
      leading == prev.trailing
      trailing == super.trailing
      width == 200
      height == prev
      bottom == super
      onAction:
        # echo "slider value: ", slider.value
        v.recalc()

  v.slider = slider
  v.content = content

  v.pathLabel = curDir

  v.content.onItemDoubleClick = proc(i: int)=
    sandbox:
      if v.currentDir.isNil: return
      var item = v.currentDir.childAt(i)
      if item.isNil: return
      if item.isComposition:
        echo "open conposition ", item.path
      elif item.isImage:
        echo "open imagepreview ", item.path
        var imagePreview = new(ImagePreview)
        imagePreview.loadImage(item.path) do():
          imagePreview.popupAtCenterOfWindow()
      elif item.isDirectory:
        tree.select(item)
      else:
        openInDefaultApp(item.path)

  v.content.onItemsDelete = proc(selectedItems: seq[int])=
    sandbox:
      echo "delete not implemented ", selectedItems
      discard
      # var path = v.currentDir.outLinePath
      # for item in selectedItems:
      #     let n = v.currentPathNodeChildren()[item]
      #     discard tryRemoveFile(n.fullPath)

      # v.reloadFileSystem()
      # v.fileSystemTree.reloadData()
      # v.fileSystemTree.selectItemAtIndexPath(path)

  v.content.onBackspace = proc() =
    sandbox:
      if v.currentDir.isNil: return
      # v.moveToDirectory(v.currentDir.parent)
      tree.select(v.currentDir.parent)

  v.content.onItemsDragStart = proc(items: seq[int])=
    sandbox:
      # var fileViews = newSeq[EditorThumbnailView](items.len)
      # var index = 0

      # for i in items:
      #     fileViews[index] = cast[EditorThumbnailView](v.content.subviews[i])
      #     inc index
      if items.len == 0 or v.currentDir.isNil: return

      var drag_data = ""
      var drag_kind = ""

      var curPath: PathNode
      for idx in items:
        var pbk = ""
        let pathNode = v.currentDir.childAt(idx)
        if pathNode.isNil: continue
        if pathNode.isComposition:
          pbk = rodPbComposition
        elif pathNode.isImage:
          pbk = rodPbSprite

        if pbk.len > 0:
          if drag_kind.len > 0:
            drag_kind = rodPbFiles
            drag_data &= ":" & pathNode.path
          else:
            drag_kind = pbk
            drag_data = pathNode.path
        curPath = pathNode

      if drag_data.len > 0 and drag_kind.len > 0 and not curPath.isNil:
        var dpi = newPasteboardItem(drag_kind, drag_data)
        var img: Image = curPath.image
        startDrag(dpi, img)


  v.content.onItemRenamed = proc(item: int) =
    discard
      # var fileView = v.content.subviews[item].EditorThumbnailView
      # fileView.rename() do(name: string):
      #     echo "renamed ", fileView.path, " to ", name
      #     setTimeout(0.1) do():
      #         discard v.window.makeFirstResponder(v.contentView)
          # discard v.contentView.makeFirstResponder()

proc recalc(v: EditorAssetsView) {.gcsafe.} =
  # let ct = epochTime()
  if v.currentDir.isNil: return

  let dirContentSize = v.currentDir.directories.len + v.currentDir.files.len
  var size = interpolate(64, 256, v.slider.value)
  var itemsPerLine = int(v.content.frame.size.width) div size
  let offset = 2.0 * (float) (int(v.content.frame.size.width) - itemsPerLine * size) / itemsPerLine #50.0
  var adjastedSize = size.float
  let topVisibleLine = int(abs(v.content.frame.origin.y)) div (adjastedSize.int + 20)
  let visibleLines = int(v.content.superview.frame.height) div (adjastedSize.int + 20) + 2
  let thumbnailsCount = min(visibleLines * itemsPerLine, dirContentSize)
  let firstYOffset = float(topVisibleLine * (adjastedSize.int + 20))
  v.content.firstItemIndex = topVisibleLine * itemsPerLine

  if v.content.offsetVar.isNil:
    v.content.offsetVar = newVariable(offset)
    v.window.layoutSolver.addEditVariable(v.content.offsetVar, MEDIUM)
  v.window.layoutSolver.suggestValue(v.content.offsetVar, offset)

  if v.content.thumbFirstLeading.isNil:
    v.content.thumbFirstLeading = selfPHS.leading == superPHS.leading
  if v.content.thumbFirstTop.isNil:
    v.content.thumbFirstTop = selfPHS.top == prevPHS.bottom
  if v.content.thumbLeading.isNil:
    v.content.thumbLeading = selfPHS.leading == prevPHS.trailing + v.content.offsetVar * 0.5
  if v.content.thumbTop.isNil:
    v.content.thumbTop = selfPHS.top == prevPHS.top

  let sizeChanged = abs(adjastedSize - v.content.currentThumbSize) > 0.001
  v.content.currentThumbSize = adjastedSize
  let firstYchanged = abs(v.content.currentFirstYOffset - firstYOffset) > 0.001
  v.content.currentFirstYOffset = firstYOffset

  let contentHeight = max((dirContentSize div itemsPerLine + 3).float * (adjastedSize + 20), v.content.superview.frame.size.height)
  let contentHeightChanged = abs(contentHeight - v.content.currentHeight) > 0.001
  v.content.currentHeight = contentHeight
  if contentHeightChanged:
    if v.content.heightConst.isNil:
      v.content.heightVar = newVariable(contentHeight)
      v.window.layoutSolver.addEditVariable(v.content.heightVar, MEDIUM)
      v.content.heightConst = selfPHS.height == v.content.heightVar
      v.content.addConstraint(v.content.heightConst)
    v.window.layoutSolver.suggestValue(v.content.heightVar, contentHeight)

  if v.thumbnails.len == 0:
    var thumb = new(EditorThumbnailView)
    thumb.makeLayout:
      leading == super.leading
      height == self.width + 20

    thumb.firstInARow = true
    v.thumbnails.add(thumb)
    v.content.addSubview(thumb)

  if sizeChanged:
    if v.content.thumbWidth.isNil:
      v.content.thumbWidth = newVariable(adjastedSize)
      v.window.layoutSolver.addEditVariable(v.content.thumbWidth, MEDIUM)
      v.content.thumbWidthConstr = selfPHS.width == v.content.thumbWidth
      v.thumbnails[0].addConstraint(v.content.thumbWidthConstr)
    v.window.layoutSolver.suggestValue(v.content.thumbWidth, adjastedSize)

  if firstYchanged:
    if v.content.thumbYOffset.isNil:
      v.content.thumbYOffset = newVariable(firstYOffset)
      v.window.layoutSolver.addEditVariable(v.content.thumbYOffset, MEDIUM)
      v.content.thumbYOffsetConstr = selfPHS.top == superPHS.top + v.content.thumbYOffset
      v.thumbnails[0].addConstraint(v.content.thumbYOffsetConstr)
    v.window.layoutSolver.suggestValue(v.content.thumbYOffset, firstYOffset)

  while v.thumbnails.len < thumbnailsCount:
    var thumb = new(EditorThumbnailView)
    thumb.makeLayout:
      width == prev
      height == prev

    thumb.addConstraint(v.content.thumbLeading)
    thumb.addConstraint(v.content.thumbTop)
    v.thumbnails.add(thumb)
    v.content.addSubview(thumb)

  for i, thumb in v.thumbnails:
    let idx = topVisibleLine * itemsPerLine + i
    thumb.hidden = idx >= dirContentSize
    if thumb.hidden: continue
    if idx != 0: # first aready have correct constraints
      let indexInaRow = idx mod itemsPerLine
      if indexInaRow == 0:
        if not thumb.firstInARow:
          thumb.firstInARow = true
          thumb.removeConstraint(v.content.thumbLeading)
          thumb.removeConstraint(v.content.thumbTop)
          thumb.addConstraint(v.content.thumbFirstTop)
          thumb.addConstraint(v.content.thumbFirstLeading)

      elif thumb.firstInARow:
        thumb.firstInARow = false
        thumb.removeConstraint(v.content.thumbFirstTop)
        thumb.removeConstraint(v.content.thumbFirstLeading)
        thumb.addConstraint(v.content.thumbLeading)
        thumb.addConstraint(v.content.thumbTop)

    let node = v.currentDir.childAt(idx)
    thumb.setup(node, adjastedSize, dirContentSize)

  if sizeChanged or firstYchanged or contentHeightChanged:
    v.setNeedsLayout()

proc thumbnailAtIndex(v: EditorScrollContentView, i: int): EditorThumbnailView =
  sandbox:
    result = cast[EditorThumbnailView](v.subviews[i - v.firstItemIndex])

proc selectItem(v: EditorScrollContentView, i: int, notify: bool = true)=
  sandbox:
    let subv = v.thumbnailAtIndex(i)
    subv.select()
    if notify and not v.onItemSelected.isNil:
      # echo "select ", i
      v.onItemSelected(i)

proc deselectItem(v: EditorScrollContentView, i: int, notify: bool = true)=
  sandbox:
    let subv = v.thumbnailAtIndex(i)
    subv.deselect()
    if notify and not v.onItemDeselected.isNil:
      # echo "deselect ", i
      v.onItemDeselected(i)

method onTouchEv*(v: EditorScrollContentView, e: var Event): bool =
  discard procCall v.View.onTouchEv(e)
  if e.buttonState == bsDown:
    v.dragStarted = false
    v.selectionRect = zeroRect
    v.selectionOrigin = e.localPosition

  elif e.buttonState == bsUnknown:
    if v.dragStarted: return false

    var orig = v.selectionOrigin
    var dragLen = v.selectionOrigin.distanceTo(e.localPosition)
    if not v.onItemsDragStart.isNil:
      for i, sub in v.subviews:
        if sub.frame.contains(orig) and not sub.hidden:
          if dragLen > 10.0:
            v.onItemsDragStart(@[i + v.firstItemIndex])
            v.dragStarted = true
            return false
          return true

    var topLeft = newPoint(0.0, 0.0)
    topLeft.x = min(orig.x, e.localPosition.x)
    topLeft.y = min(orig.y, e.localPosition.y)

    var botRight = newPoint(0.0, 0.0)
    botRight.x = max(orig.x, e.localPosition.x)
    botRight.y = max(orig.y, e.localPosition.y)

    v.selectionRect.origin = topLeft
    v.selectionRect.size = newSize(botRight.x - topLeft.x, botRight.y - topLeft.y)

    for i, subv in v.subviews:
      if subv.frame.intersect(v.selectionRect):
        v.selectItem(i + v.firstItemIndex, false)
      else:
        v.deselectItem(i + v.firstItemIndex, false)

  else:
    if v.dragStarted:
      # echo "draging"
      # v.selectedItems.setLen(0)
      v.selectionRect = zeroRect
    else:
      let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 5.0
      var selected = newSeq[int]()

      if hasSelectionRect:
        # echo "hasSelectionRect"
        for i, subv in v.subviews:
          if subv.frame.intersect(v.selectionRect):
            v.selectItem(i + v.firstItemIndex, false)
            selected.add(i + v.firstItemIndex)
          elif i in v.selectedItems:
            v.deselectItem(i + v.firstItemIndex)
      else:
        if v.selectedItems.len > 1:
          # echo "selitems > 1"
          for si in v.selectedItems:
            if v.subviews[si - v.firstItemIndex].frame.contains(v.selectionOrigin):
              v.selectItem(si)
              selected.add(si)
            else:
              v.deselectItem(si)

          v.selectedItems.setLen(0)
        else:
          var dc = newSeq[int]()

          for idx, subv in v.subviews:
            let i = idx + v.firstItemIndex
            if subv.frame.contains(v.selectionOrigin):
              if i in v.selectedItems and not v.onItemDoubleClick.isNil:
                dc.add(i)
                # v.deselectItem(i)
                # v.onItemDoubleClick(i)
                v.selectedItems.setLen(0)
              else:
                v.selectItem(i)
                selected.add(i)

            elif i in v.selectedItems:
              v.deselectItem(i)

          for i in dc:
            v.deselectItem(i)
            v.onItemDoubleClick(i)

      v.selectedItems = selected
      v.selectionRect = zeroRect

  result = true
  discard v.makeFirstResponder()

method draw*(v: EditorScrollContentView, r: Rect)=
  procCall v.View.draw(r)
  let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 0.1
  if hasSelectionRect:
    let c = currentContext()
    c.strokeColor = newColor(0.0, 0.0, 0.5, 0.5)
    c.strokeWidth = 1.0
    c.fillColor = uiSelectionColor
    c.drawRect(v.selectionRect)

method onKeyDown*(v: EditorScrollContentView, e: var Event):bool=
  if not v.isFirstResponder: return
  case e.keyCode:

  of VirtualKey.Delete:
      if v.subviews.len == 0: return
      if not v.onItemsDelete.isNil and v.selectedItems.len > 0:
          v.onItemsDelete(v.selectedItems)
          v.selectedItems.setLen(0)

      result = true

  of VirtualKey.Up, VirtualKey.Down, VirtualKey.Left, VirtualKey.Right:
    if v.subviews.len == 0: return
    if v.selectedItems.len == 0:
      v.selectedItems.add(v.firstItemIndex)
      v.selectItem(v.firstItemIndex)
    else:
      let itemsInLine = v.itemsInARow
      var step = if e.keyCode == VirtualKey.Left: -1
                elif e.keyCode == VirtualKey.Right: 1
                elif e.keyCode == VirtualKey.Up: -itemsInLine
                else: itemsInLine

      var last = -1
      if not e.modifiers.anyCtrl():
        for sel in v.selectedItems:
          last = sel
          v.deselectItem(sel)

        v.selectedItems.setLen(0)
      else:
        last = v.selectedItems[^1]

      step = clamp(step + (last - v.firstItemIndex), 0, v.subviews.len - 1)
      if not v.subviews[step].hidden:
        v.selectedItems.add(step + v.firstItemIndex)

      for sel in v.selectedItems:
        last = sel
        v.selectItem(sel)

    result = true

  of VirtualKey.Space:
    if v.subviews.len == 0: return
    if v.selectedItems.len == 1 and not v.onItemDoubleClick.isNil:
      v.onItemDoubleClick(v.selectedItems[0])
      result = true

  of VirtualKey.Backspace:
    if not v.onBackspace.isNil():
      v.onBackspace()
      result = true

  of VirtualKey.Return:
    if v.subviews.len == 0: return
    if v.selectedItems.len == 1 and not v.onItemRenamed.isNil:
      v.onItemRenamed(v.selectedItems[0])
      result = true

  else: discard

method clipType*(v: EditorScrollContentView): ClipType = ctDefaultClip

method viewWillMoveToWindow*(v: EditorScrollContentView, w: Window) =
  echo "EditorScrollContentView viewWillMoveToWindow ", w.isNil
  if w.isNil and not v.window.isNil:
    v.removeAllSubviews()
    # these are removed by removeAllSubviews
    v.thumbWidthConstr = nil
    v.thumbYOffsetConstr = nil
    v.thumbLeading = nil
    v.thumbTop = nil
    v.thumbFirstLeading = nil
    v.thumbFirstTop = nil

    if not v.assetsView.isNil:
      v.assetsView.thumbnails.setLen(0)
    if not v.heightConst.isNil:
      v.removeConstraint(v.heightConst)
      v.heightConst = nil

    let s = v.window.layoutSolver
    if not v.heightVar.isNil:
      if s.hasEditVariable(v.heightVar):
        s.removeEditVariable(v.heightVar)
      v.heightVar = nil
    if not v.thumbWidth.isNil:
      if s.hasEditVariable(v.thumbWidth):
        s.removeEditVariable(v.thumbWidth)
      v.thumbWidth = nil
    if not v.thumbYOffset.isNil:
      if s.hasEditVariable(v.thumbYOffset):
        s.removeEditVariable(v.thumbYOffset)
      v.thumbYOffset = nil
    if not v.offsetVar.isNil:
      if s.hasEditVariable(v.offsetVar):
        s.removeEditVariable(v.offsetVar)
      v.offsetVar = nil

  procCall v.View.viewWillMoveToWindow(w)

method viewDidMoveToWindow*(v: EditorScrollContentView) =
  procCall v.View.viewDidMoveToWindow()
  if v.window.isNil: return
  v.currentFirstYOffset = -1
  v.currentThumbSize = -1
  v.currentHeight = -1
  if not v.assetsView.isNil:
    v.assetsView.recalc()