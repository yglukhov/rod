import std/[os, algorithm, tables, deques, sets]
import nimx / [ image, context, types, render_to_image ]
import ./fileicon_loader

var gCachedStandartIcons {.threadVar.}: TableRef[string, Image]
var gDirImageCache {.threadVar.}: TableRef[string, Image]
var gLoadingQueue {.threadVar.}: Deque[string]
var gCurrentLoadings {.threadVar.}: HashSet[string]

const imageSize = 128
const concurrentLoaders = 8

type
  PathNode* = ref object
    path*: string
    name*: string
    ext*: string
    isDirectory*: bool
    files*: seq[PathNode]
    directories*: seq[PathNode]
    parent*: PathNode

proc isComposition*(p: PathNode): bool = p.ext == ".jcomp"
proc isImage*(p:PathNode): bool = p.ext in [".png", ".jpg", ".jpeg", ".gif", ".tif", ".tiff", ".tga", ".pvr", ".webp"]

proc image*(n: PathNode): Image =
  if n.isImage:
    result = gDirImageCache.getOrDefault(n.path)
  if result.isNil:
    result = gCachedStandartIcons.getOrDefault(n.ext)

proc scaleDownImage(i: Image): Image {.gcsafe.} =
  result = i
  if result.size.width > imageSize or result.size.height > imageSize:
    let c = currentContext()
    if result.size.width > imageSize or result.size.height > imageSize:
      let scale = imageSize/max(result.size.width, result.size.height)
      var resultImage = imageWithSize(newSize(imageSize, imageSize))
      resultImage.draw:
        c.drawImage(result, newRect(1, 1, result.size.width * scale - 1, result.size.height * scale - 1))
      result = resultImage

proc loadIconForExtension(n: PathNode, cb: proc(){.gcsafe.}) =
  var cachedImage = gCachedStandartIcons.getOrDefault(n.ext)
  if cachedImage.isNil:
    loadIconForPath(n.path, 128) do(i: Image) {.gcsafe.}:
      gCachedStandartIcons[n.ext] = i.scaleDownImage()
      cb()
    return
  cb()

proc loadThumbnailForImage(n: PathNode) =
  proc loadImageAUX(path: string) {.gcsafe.} =
    loadImagePreview(path, 128) do(i: Image) {.gcsafe.}:
        gDirImageCache[path] = i.scaleDownImage()
        gCurrentLoadings.excl(path)
        if gLoadingQueue.len > 0:
          let next = gLoadingQueue.popFirst()
          loadImageAUX(next)

  var cachedImage = gDirImageCache.getOrDefault(n.path)
  if cachedImage.isNil:
    if gCurrentLoadings.len > concurrentLoaders:
      gLoadingQueue.addFirst(n.path)
    else:
      gCurrentLoadings.incl(n.path)
      loadImageAUX(n.path)

proc loadImage(n: PathNode) =

  if gCachedStandartIcons.isNil:
    gCachedStandartIcons = newTable[string, Image]()
  if gDirImageCache.isNil:
    gDirImageCache = newTable[string, Image]()

  n.loadIconForExtension() do():
    if n.isImage:
      n.loadThumbnailForImage()

proc childAt*(p: PathNode, i: int): PathNode =
  let dirlen = p.directories.len
  if i < dirlen:
    return p.directories[i]
  if i < p.files.len + dirlen:
    return p.files[i - dirlen]

proc getNodePath*(n: PathNode): seq[int] =
  if n.isNil:
    return @[]

  var node = n
  while node.parent != nil:
    var i = node.parent.directories.find(node)
    result.insert(i, 0)
    node = node.parent

proc expand(p: PathNode) =
  for kind, path in walkDir(p.path):
    let sp = splitFile(path)
    var child = PathNode(
      path: path, name: sp.name, isDirectory: kind == pcDir or kind == pcLinkToDir, parent: p,
      ext: sp.ext
    )

    if sp.name.len > 0 and sp.name[0] == '.':
        continue
    if child.isDirectory:
      p.directories.add(child)
      child.expand()
    else:

      p.files.add(child)

  p.directories.sort do(a,b: PathNode) -> int:
    result = cmp(a.name, b.name)

  p.files.sort do(a,b: PathNode) -> int:
    result = cmp(splitFile(a.path).ext, splitFile(b.path).ext)
    if result == 0:
      result = cmp(a.name, b.name)

  for dir in p.directories:
    dir.loadImage()
  for file in p.files:
    file.loadImage()

proc newRootPathNode*(path: string): PathNode =
  result = PathNode(path: path, name: splitFile(path).name, isDirectory: true)
  result.expand()
