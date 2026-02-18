import std/[tables, math]
import kiwi
import nimx / [ view, types, layout, text_field, context, image, formatted_text ]
import ../[editor_view_types]
import ./[path_node, fileicon_loader]

const imageSize = 128.Coord

type
  EditorAssetImageView* = ref object of View
    image*: Image
    rtiImage: SelfContainedImage
    thumb: EditorThumbnailView

  EditorThumbnailView* = ref object of View
    path: string
    imageView*: EditorAssetImageView
    pathLabel: Label
    gridConstraints*: seq[Constraint]
    imageHeightConstr*: Constraint
    curItem: PathNode
    parentDir: PathNode
    selected: bool
    currentSize: Coord
    firstInARow*: bool
    lastInARow*: bool
    loadingInProgressForNode: PathNode

method draw*(v: EditorAssetImageView, r: Rect) =
  if v.thumb.isNil or v.thumb.curItem.isNil or v.thumb.curItem.image.isNil: return
  currentContext().drawImage(v.thumb.curItem.image, r)

method init*(v: EditorThumbnailView) =
  procCall v.View.init()

  v.makeLayout:
    - EditorAssetImageView as imageView:
      top == super
      leading == super.leading
      trailing == super.trailing
      bottom == next.top
      backgroundColor: uiPink
    - Label as title:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing
      height == 20
      bottom == super
      text: "not.set"

  v.pathLabel = title
  v.imageView = imageView
  v.imageView.thumb = v

proc select*(v: EditorThumbnailView) =
  v.selected = true
  v.pathLabel.formattedText.boundingSize = newSize(2 * v.currentSize.Coord, 20)
  v.backgroundColor = uiSelectionColor

proc deselect*(v: EditorThumbnailView) =
  v.selected = false
  v.pathLabel.formattedText.boundingSize = newSize(v.currentSize.Coord, 20)
  v.backgroundColor = clearColor()

proc setup*(v: EditorThumbnailView, n: PathNode, size: float, dirSize: int) =
  v.deselect()
  if v.curItem != n:
    v.imageView.image = nil

  if n == nil:
    v.pathLabel.text = "not.set"
    return

  v.curItem = n
  v.parentDir = v.curItem.parent

  v.currentSize = size
  v.pathLabel.formattedText.boundingSize = newSize(v.currentSize, 20)
  v.pathLabel.formattedText.truncationBehavior = tbCut
  v.pathLabel.formattedText.horizontalAlignment = haCenter
  v.pathLabel.formattedText.verticalAlignment = vaTop
  v.pathLabel.text = n.name
