import std/[tables, math]
import kiwi
import nimx / [ view, types, layout, text_field, context, image, formatted_text, render_to_image, portable_gl ]
import ../[editor_view_types]
import ./[path_node, fileicon_loader]

var gCachedStandartIcons {.threadVar.}: TableRef[string, Image]
var gDirImageCache {.threadVar.}: TableRef[string, Image]

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
  if v.image.isNil: return
  let c = currentContext()
  if v.image.size.width > imageSize or v.image.size.height > imageSize:
    let scale = imageSize/max(v.image.size.width, v.image.size.height)
    v.rtiImage = imageWithSize(newSize(imageSize, imageSize))
    v.rtiImage.draw:
      c.drawImage(v.image, newRect(1, 1, v.image.size.width * scale - 1,v.image.size.height * scale - 1))

    v.image = v.rtiImage
    if not v.thumb.curItem.isNil:
      gDirImageCache[v.thumb.curItem.path] = v.image
    v.rtiImage = nil

  c.drawImage(v.image, r)

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
  if v.curItem.parent != v.parentDir:
    if gDirImageCache.isNil:
      gDirImageCache = newTable[string, Image]()
    # gDirImageCache.clear()
  v.parentDir = v.curItem.parent

  v.currentSize = size
  v.pathLabel.formattedText.boundingSize = newSize(v.currentSize, 20)
  v.pathLabel.formattedText.truncationBehavior = tbCut
  v.pathLabel.formattedText.horizontalAlignment = haCenter
  v.pathLabel.formattedText.verticalAlignment = vaTop
  v.pathLabel.text = n.name
  if gCachedStandartIcons.isNil:
    gCachedStandartIcons = newTable[string, Image]()

  if v.imageView.image.isNil:
    if n.isImage:
      let cachedImage = gDirImageCache.getOrDefault(n.path)
      if cachedImage.isNil:
        if v.loadingInProgressForNode == nil or n != v.loadingInProgressForNode:
          v.loadingInProgressForNode = n
          loadImagePreview(n.path, 128) do(i: Image) {.gcsafe.}:
            if v.loadingInProgressForNode == n:
              v.imageView.image = i
              gDirImageCache[n.path] = cachedImage
              v.loadingInProgressForNode = nil
      else:
        v.imageView.image = cachedImage
    else:
      let cachedImage = gCachedStandartIcons.getOrDefault(n.ext)
      if cachedImage.isNil:
        if v.loadingInProgressForNode == nil or n != v.loadingInProgressForNode:
          v.loadingInProgressForNode = n
          loadIconForPath(n.path, 128) do(i: Image) {.gcsafe.}:
            if v.loadingInProgressForNode == n:
              v.imageView.image = i
              gCachedStandartIcons[n.ext] = v.imageView.image
              v.loadingInProgressForNode = nil
      else:
        v.imageView.image = cachedImage
