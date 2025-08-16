import std/[ math, tables, times ]
import kiwi
import nimx / [
  view, types, slider, layout, scroll_view, text_field, image, animation, drag_and_drop,
  layout_vars, formatted_text, context, view_event_handling, event, image_preview
  ]
import nimx/pasteboard/pasteboard_item
import ../[editor_view_types]
import ./[editor_assets_tree, path_node, fileicon_loader, editor_assets_thumbnail]

when not defined(android) and not defined(ios) and not defined(emscripten):
  import os_files/file_info

type
  EditorScrollContentView = ref object of View
      # mousevents
    assetsView: EditorAssetsView
    heightVar: Variable
    heightConst: Constraint
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
    dontUpdate: bool
    currentDir: PathNode
    pathLabel: Label
    prevFrame: Rect
    predefinedConstraints: array[16, Constraint]
    currentThumbSize: float
    currentFirstYOffset: float

proc recalc(v: EditorAssetsView) {.gcsafe.}

method updateLayout*(v: EditorAssetsView) =
  procCall v.View.updateLayout()
  if v.dontUpdate:
    v.dontUpdate = false
    return

  # if v.frame == v.prevFrame:
  #   return

  # v.prevFrame = v.frame
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
    backgroundColor: uiBackground
    - EditorAssetsTreeView as tree:
      top == super
      leading == super
      width >= 200 @ WEAK
      bottom == super
      onSelectionChanged do(p: PathNode):
        v.moveToDirectory(p)

    - ScrollView:
      top == super
      leading == prev.trailing
      trailing == super
      backgroundColor: uiAccent
      - EditorScrollContentView as content:
        leading == super
        trailing == super
        assetsView: v

    - Label as curDir:
      backgroundColor: uiBlue
      top == prev.bottom
      leading == super
      height == 20
      text: "Current path"

    - Slider as slider:
      backgroundColor: uiHighlight
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
      if item.isComposition:
        echo "open conposition ", item.path
      elif item.isImage:
        echo "open imagepreview ", item.path
        var imagePreview = new(ImagePreview)
        imagePreview.loadImage(item.path) do():
          imagePreview.popupAtCenterOfWindow()
      elif item.isDirectory:
        tree.select(item)
        # v.moveToDirectory(item)
      else:
        openInDefaultApp(item.path)
      # let idx = i
      # setTimeout(0.1) do():
      # var fileView = v.content.subviews[idx].EditorThumbnailView
      # fileView.doubleClicked()

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

      for idx in items:
        var pbk = ""
        let pathNode = v.currentDir.childAt(idx)
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

      if drag_data.len > 0 and drag_kind.len > 0:
        var dpi = newPasteboardItem(drag_kind, drag_data)
        var img: Image = v.thumbnails[items[0]].imageView.image
        startDrag(dpi, img)
      # if not v.mOnDragStart.isNil:
      #     v.mOnDragStart(fileViews)

  v.content.onItemRenamed = proc(item: int) =
    discard
      # var fileView = v.content.subviews[item].EditorThumbnailView
      # fileView.rename() do(name: string):
      #     echo "renamed ", fileView.path, " to ", name
      #     setTimeout(0.1) do():
      #         discard v.window.makeFirstResponder(v.contentView)
          # discard v.contentView.makeFirstResponder()

type Ct {.pure.} = enum
  leading = 0
  defaultLeading
  defaultTop
  trailing
  topPrev
  widthAdj
  heightAdj
  contentSize
  firstYOffset

proc recalcNew(v: EditorAssetsView) {.gcsafe.} =
  # v.dontUpdate = true
  let ct = epochTime()
  if v.currentDir.isNil: return

  let dirContentSize = v.currentDir.directories.len + v.currentDir.files.len
  let offset = 50.0
  var size = interpolate(64, 256, v.slider.value)
  var itemsPerLine = int(v.content.frame.size.width) div size
  var adjastedSize = size.float #v.content.frame.size.width / float(itemsPerLine) - (offset * 0.5)
  let topVisibleLine = int(abs(v.content.frame.origin.y)) div (size + 20)
  let visibleLines = int(v.content.superview.frame.height) div (size + 20) + 1
  let bottomVisibleLine = visibleLines + topVisibleLine
  let thumbnailsCount = min(visibleLines * itemsPerLine, dirContentSize)
  let firstYOffset = topVisibleLine * (size + 20)

  if v.predefinedConstraints[Ct.leading.int] == nil:
    v.predefinedConstraints[Ct.leading.int] = selfPHS.leading == superPHS.leading
  if v.predefinedConstraints[Ct.topPrev.int] == nil:
    v.predefinedConstraints[Ct.topPrev.int] = selfPHS.top == prevPHS.bottom

  if v.predefinedConstraints[Ct.defaultLeading.int] == nil:
    v.predefinedConstraints[Ct.defaultLeading.int] = selfPHS.leading == prevPHS.trailing

  if v.predefinedConstraints[Ct.defaultTop.int] == nil:
    v.predefinedConstraints[Ct.defaultTop.int] = selfPHS.top == prevPHS.top
  # if v.predefinedConstraints[Ct.trailing.int] == nil:
  #   v.predefinedConstraints[Ct.trailing.int] = selfPHS.trailing == superPHS.trailing

  let sizeChanged = abs(adjastedSize - v.currentThumbSize) > 0.001
  v.currentThumbSize = adjastedSize

  var contentHeight = max((dirContentSize div itemsPerLine + 3).float * (adjastedSize + 20), v.content.superview.frame.size.height)
  if v.content.heightConst.isNil:
    v.content.heightVar = newVariable(contentHeight)
    v.content.window.layoutSolver.addEditVariable(v.content.heightVar, contentHeight)
    v.content.heightConst = selfPHS.height == v.content.heightVar
    v.content.addConstraint(v.content.heightConst)
  else:
    v.content.window.layoutSolver.suggestValue(v.content.heightVar, contentHeight)

  if v.thumbnails.len == 0:
    var thumb = new(EditorThumbnailView)
    thumb.makeLayout:
      leading == super.leading
      # top == super.top
      height == self.width + 20

    v.predefinedConstraints[Ct.firstYOffset.int] = selfPHS.top == superPHS.top + firstYOffset.float
    thumb.addConstraint(v.predefinedConstraints[Ct.firstYOffset.int])
    thumb.firstInARow = true
    v.thumbnails.add(thumb)
    v.content.addSubview(thumb)

  if sizeChanged:
    if not v.predefinedConstraints[Ct.widthAdj.int].isNil:
      v.thumbnails[0].removeConstraint(v.predefinedConstraints[Ct.widthAdj.int])
    v.predefinedConstraints[Ct.widthAdj.int] = selfPHS.width == adjastedSize
    v.thumbnails[0].addConstraint(v.predefinedConstraints[Ct.widthAdj.int])

  let firstYchanged = abs(v.currentFirstYOffset - firstYOffset.float) > 0.001
  if firstYchanged:
    if not v.predefinedConstraints[Ct.firstYOffset.int].isNil:
      v.thumbnails[0].removeConstraint(v.predefinedConstraints[Ct.firstYOffset.int])
    v.predefinedConstraints[Ct.firstYOffset.int] = selfPHS.top == superPHS.top + firstYOffset.float
    v.thumbnails[0].addConstraint(v.predefinedConstraints[Ct.firstYOffset.int])
    # echo "firstYOffset ", firstYOffset
    v.currentFirstYOffset = firstYOffset.float

  while v.thumbnails.len < thumbnailsCount:
    var thumb = new(EditorThumbnailView)
    thumb.makeLayout:
      width == prev
      height == prev

    thumb.addConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
    thumb.addConstraint(v.predefinedConstraints[Ct.defaultTop.int])
    v.thumbnails.add(thumb)
    v.content.addSubview(thumb)

  for i, thumb in v.thumbnails:
    let idx = topVisibleLine * itemsPerLine + i
    thumb.hidden = idx >= dirContentSize
    if thumb.hidden: continue
    # let row = idx div itemsPerLine
    if idx != 0:
      let indexInaRow = idx mod itemsPerLine
      if indexInaRow == 0: # first aready have correct constraints
        if not thumb.firstInARow:
          thumb.firstInARow = true
          thumb.removeConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
          thumb.removeConstraint(v.predefinedConstraints[Ct.defaultTop.int])
          thumb.addConstraint(v.predefinedConstraints[Ct.topPrev.int])
          thumb.addConstraint(v.predefinedConstraints[Ct.leading.int])

      elif thumb.firstInARow:
        thumb.firstInARow = false
        thumb.removeConstraint(v.predefinedConstraints[Ct.topPrev.int])
        thumb.removeConstraint(v.predefinedConstraints[Ct.leading.int])
        thumb.addConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
        thumb.addConstraint(v.predefinedConstraints[Ct.defaultTop.int])

    let node = v.currentDir.childAt(idx)
    thumb.setup(node, adjastedSize, dirContentSize)

  if sizeChanged or firstYchanged:
    v.setNeedsLayout()

  echo "recalcNew: ", epochTime() - ct, " visibleLines ", visibleLines, " size ", adjastedSize, " topIndex ", topVisibleLine * itemsPerLine, " content ", v.content.frame #, " adjsize ", adjastedSize, " sizeChanged ", sizeChanged,  " thumbs ", dirContentSize, " perLine ", itemsPerLine #, " H ", contentH, " items ", dirContentSize, " line ", itemsPerLine, " top ", topVisibleLine

    # let nodeName = if node.isNil: "nil" else: node.name
    # echo "view i ", i, " global i ", idx, " visible ", nodename, " in ", [topVisibleLine, bottomVisibleLine], " frame ", thumb.frame

  # while v.thumbnails.len < dirContentSize:
  #   var thumb = new(EditorThumbnailView)
  #   thumb.makeLayout:
  #     width == prev
  #     height == prev

  #   thumb.addConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
  #   thumb.addConstraint(v.predefinedConstraints[Ct.defaultTop.int])
  #   v.thumbnails.add(thumb)
  #   v.content.addSubview(thumb)

  # for idx, thumb in v.thumbnails:
  #   thumb.hidden = idx >= dirContentSize
  #   if thumb.hidden: continue
  #   let row = idx div itemsPerLine
  #   if idx != 0:
  #     let indexInaRow = idx mod itemsPerLine
  #     if indexInaRow == 0: # first aready have correct constraints
  #       if not thumb.firstInARow:
  #         thumb.firstInARow = true
  #         thumb.removeConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
  #         thumb.removeConstraint(v.predefinedConstraints[Ct.defaultTop.int])
  #         thumb.addConstraint(v.predefinedConstraints[Ct.topPrev.int])
  #         thumb.addConstraint(v.predefinedConstraints[Ct.leading.int])

  #     elif thumb.firstInARow:
  #       thumb.firstInARow = false
  #       thumb.removeConstraint(v.predefinedConstraints[Ct.topPrev.int])
  #       thumb.removeConstraint(v.predefinedConstraints[Ct.leading.int])
  #       thumb.addConstraint(v.predefinedConstraints[Ct.defaultLeading.int])
  #       thumb.addConstraint(v.predefinedConstraints[Ct.defaultTop.int])

  #   let node = v.currentDir.childAt(idx)
  #   thumb.setup(node, adjastedSize, dirContentSize)
  #   if row >= topVisibleLine and row < bottomVisibleLine:
  #     let nodeName = if node.isNil: "nil" else: node.name
  #     echo row, " visible ", nodename, " in ", [topVisibleLine, bottomVisibleLine]
    # let si = v.content.subviews.find(thumb.View)
    # echo si, " SETUP: ", nodename, " FIRST: ", thumb.firstInARow, " FRAME: ", thumb.frame


proc recalcOld(v: EditorAssetsView) {.gcsafe.} =
  v.dontUpdate = true
  let ct = epochTime()
  for idx, thumb in v.thumbnails:
    for constr in thumb.gridConstraints:
      thumb.removeConstraint(constr)
    thumb.gridConstraints.setLen(0)
    if not thumb.imageHeightConstr.isNil:
      thumb.imageView.removeConstraint(thumb.imageHeightConstr)
      thumb.imageHeightConstr = nil

  var pt0 = epochTime()
  v.content.removeAllSubviews()

  if v.currentDir.isNil: return
  var pt1 = epochTime()

  let dirContentSize = v.currentDir.directories.len + v.currentDir.files.len
  while v.thumbnails.len < dirContentSize:
    v.thumbnails.add(new(EditorThumbnailView))

  let offset = 50.0
  var size = interpolate(64, 256, v.slider.value)
  var itemsPerRow = int(v.content.frame.size.width) div size
  v.content.itemsInARow = itemsPerRow
  if itemsPerRow == 0: return
  var adjastedSize = v.content.frame.size.width / float(itemsPerRow) - (offset * 0.5)
  # echo " adjastedSize ", adjastedSize, " itemsPerRow ", itemsPerRow
  # for idx, thumb in v.thumbnails:
  for idx in 0 ..< dirContentSize:
    let thumb = v.thumbnails[idx]
    let row = idx div itemsPerRow
    let rowOfPrevItem = (idx - 1) div itemsPerRow
    let indexInaRow = idx mod itemsPerRow

    var topConstr: Constraint
    if row == 0 and indexInaRow == 0:
      topConstr = thumb.layout.vars.top == superPHS.top + offset * 0.5
    elif rowOfPrevItem == row:
      topConstr = thumb.layout.vars.top == prevPHS.top
    else:
      topConstr = thumb.layout.vars.top == prevPHS.bottom + offset * 0.5

    var leadingConstr: Constraint
    if indexInaRow == 0:
      leadingConstr = thumb.layout.vars.x == superPHS.x + offset * 0.25
    else:
      leadingConstr = thumb.layout.vars.leading == prevPHS.trailing + offset * 0.5

    thumb.gridConstraints.add(topConstr)
    thumb.gridConstraints.add(leadingConstr)
    thumb.gridConstraints.add(thumb.layout.vars.width == adjastedSize.Coord)

    thumb.imageHeightConstr = thumb.imageView.layout.vars.height == adjastedSize.Coord
    thumb.imageView.addConstraint(thumb.imageHeightConstr)
    thumb.setup(v.currentDir.childAt(idx), adjastedSize, dirContentSize)

    # if idx == v.thumbnails.len - 1:
    #   thumb.gridConstraints.add(thumb.layout.vars.bottom == superPHS.bottom)

    for constr in thumb.gridConstraints:
      thumb.addConstraint(constr)

    v.content.addSubview(thumb)
  echo "recalc: ", epochTime() - ct, " p0 ", pt0 - ct, " p1 ", pt1 - ct, " con ", v.content.frame , " pos ", cast[ScrollView](v.content.superview).scrollPosition

proc recalc(v: EditorAssetsView) {.gcsafe.} =
  recalcNew(v)
  # recalcOld(v)

proc thumbnailAtIndex(v: EditorScrollContentView, i: int): EditorThumbnailView =
  sandbox:
    result = cast[EditorThumbnailView](v.subviews[i])

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
    # for si in v.selectedItems:
    #   v.deselectItem(si)
    # v.selectedItems.setLen(0)

  elif e.buttonState == bsUnknown:
    if v.dragStarted: return false

    var orig = v.selectionOrigin
    var dragLen = v.selectionOrigin.distanceTo(e.localPosition)
    if not v.onItemsDragStart.isNil:
      for i, sub in v.subviews:
        if sub.frame.contains(orig):
          # v.selectedItems.setLen(0)
          if dragLen > 10.0:
            # sub.backgroundColor = selectionColor
            v.onItemsDragStart(@[i])
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
        v.selectItem(i, false)
      else:
        v.deselectItem(i, false)

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
            v.selectItem(i, false)
            selected.add(i)
          elif i in v.selectedItems:
            v.deselectItem(i)
      else:
        if v.selectedItems.len > 1:
          # echo "selitems > 1"
          for si in v.selectedItems:
            if v.subviews[si].frame.contains(v.selectionOrigin):
              v.selectItem(si)
              selected.add(si)
            else:
              v.deselectItem(si)

          v.selectedItems.setLen(0)
        else:
          var dc = newSeq[int]()

          for i, subv in v.subviews:
            # echo "subv nil ", subv.isNil, " ", v.isNil
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
      v.selectedItems.add(0)
      v.selectItem(0)
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

      step = clamp(step + last, 0, v.subviews.len - 1)
      v.selectedItems.add(step)

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
  if w.isNil and not v.window.isNil and not v.heightConst.isNil:
    v.removeConstraint(v.heightConst)
    v.heightConst = nil
    let s = v.window.layoutSolver
    if s.hasEditVariable(v.heightVar):
      s.removeEditVariable(v.heightVar)
    v.heightVar = nil

  procCall v.View.viewWillMoveToWindow(w)

method viewDidMoveToWindow*(v: EditorScrollContentView) =
  procCall v.View.viewDidMoveToWindow()
  if not v.assetsView.isNil and not v.window.isNil:
    v.assetsView.recalc()
