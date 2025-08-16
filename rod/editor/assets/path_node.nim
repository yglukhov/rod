import std/[os, algorithm]

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

proc newRootPathNode*(path: string): PathNode =
  result = PathNode(path: path, name: splitFile(path).name, isDirectory: true)
  result.expand()
