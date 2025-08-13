import std/[tables, math]
import kiwi
import nimx / [ view, types, layout, text_field, context, image, formatted_text, render_to_image, portable_gl ]
import ../[editor_view_types]
import ./[path_node, fileicon_loader]

var gCachedStandartIcons {.threadVar.}: TableRef[string, Image]
var gDirImageCache {.threadVar.}: seq[tuple[i:Image, p:string]]

const imageSize = 128.Coord

type
  EditorAssetImageView = ref object of View
    image: Image
    rtiImage: SelfContainedImage

  EditorThumbnailView* = ref object of View
    path: string
    imageView*: EditorAssetImageView
    pathLabel: Label
    gridConstraints*: seq[Constraint]
    imageHeightConstr*: Constraint
    curItem: PathNode

method draw*(v: EditorAssetImageView, r: Rect) =
  if v.image.isNil: return
  let c = currentContext()
  if v.image.size.width > imageSize or v.image.size.height > imageSize:
    let scale = imageSize/max(v.image.size.width, v.image.size.height)
    v.rtiImage = imageWithSize(newSize(imageSize, imageSize))
    v.rtiImage.draw:
      c.drawImage(v.image, newRect(0,0,v.image.size.width*scale,v.image.size.height*scale))

    v.image = v.rtiImage
    v.rtiImage = nil

  c.drawImage(v.image, r)

method init*(v: EditorThumbnailView) =
  procCall v.View.init()

  v.makeLayout:
    - EditorAssetImageView as imageView:
      top == super
      leading == super.leading
      trailing == super.trailing
      # height == 128
      backgroundColor: uiPink
    - Label as title:
      top == prev.bottom
      leading == super.leading
      trailing == super.trailing
      height == 20
      bottom == super
      text: "file.name"

  v.pathLabel = title
  v.imageView = imageView

proc setup*(v: EditorThumbnailView, n: PathNode, size: float, dirSize: int) =
  if v.curItem != n:
    v.imageView.image = nil

  v.curItem = n
  if gDirImageCache.len != dirSize:
    gDirImageCache.setLen(0)
  gDirImageCache.setLen(dirSize)

  v.pathLabel.formattedText.boundingSize = newSize(size.Coord, 20)
  v.pathLabel.formattedText.truncationBehavior = tbCut
  v.pathLabel.text = n.name
  if gCachedStandartIcons.isNil:
    gCachedStandartIcons = newTable[string, Image]()

  if v.imageView.image.isNil:
    if n.ext in [".jpg", ".png", ".webp"]:
      var found = false
      for entry in gDirImageCache:
        if entry.p == n.path:
          v.imageView.image = entry.i
          found = true

      if not found:
        loadImagePreview(n.path, 128) do(i: Image) {.gcsafe.}:
          v.imageView.image = i
          gDirImageCache.add((i: i, p: n.path))
    else:
      let cachedImage = gCachedStandartIcons.getOrDefault(n.ext)
      if cachedImage.isNil:
        loadIconForPath(n.path, 128) do(i: Image) {.gcsafe.}:
          v.imageView.image = i
          gCachedStandartIcons[n.ext] = v.imageView.image
      else:
        v.imageView.image = cachedImage
