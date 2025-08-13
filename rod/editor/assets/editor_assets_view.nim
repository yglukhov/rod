import std/[ math, tables, times ]
import kiwi
import nimx / [
  view, types, slider, layout, scroll_view, text_field, image, animation,
  layout_vars, formatted_text, context
  ]
import ../[editor_view_types]
import ./[editor_assets_tree, path_node, fileicon_loader, editor_assets_thumbnail]

type
  EditorScrollContentView = ref object of View
  EditorAssetsView* = ref object of View
    slider: Slider
    content: View
    thumbnails: seq[EditorThumbnailView]
    dontUpdate: bool
    currentDir: PathNode
    pathLabel: Label
    prevFrame: Rect

method clipType*(v: EditorScrollContentView): ClipType = ctDefaultClip

proc recalc(v: EditorAssetsView) {.gcsafe.}

method updateLayout*(v: EditorAssetsView) =
  procCall v.View.updateLayout()
  if v.dontUpdate:
    v.dontUpdate = false
    return
  if v.frame != v.prevFrame:
    v.recalc()
    v.prevFrame = v.frame

proc moveToDirectory(v: EditorAssetsView, p: PathNode) =
  v.currentDir = p
  echo "EditorAssetsView curDit: ", p.path
  v.recalc()
  v.pathLabel.text = p.path

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

proc recalc(v: EditorAssetsView) {.gcsafe.} =
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
  echo "recalc: ", epochTime() - ct, " p0 ", pt0 - ct, " p1 ", pt1 - ct
