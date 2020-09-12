import nimx / [view, types, outline_view, linear_layout,
    scroll_view, table_view_cell, text_field, button, timer]
import editor_asset_icon_view, editor_asset_container_view
import os, algorithm, hashes, tables, times
import variant

export editor_asset_icon_view
export editor_asset_container_view

type FileSystemView* = ref object of View
    rootPath*: string
    rootName*: string

    contentView*: AssetContainerView
    fileSystemTree*: OutlineView

    resourceRoot*: PathNode
    mCurrentPathNode*: PathNode

    cachedResources*: Table[string, FilePreview]

    lastFSReload*: float
    lastFSHash*: string

    mFilter: proc(pathEntry: tuple[kind: PathComponent, path: string]):bool
    mFilterContent: proc(path: string): bool
    mOnDragStart: proc(items: seq[FilePreview])
    mOnDoubleClicked: proc(item: FilePreview)
    mOnPathChanged: proc(np: string)
    mCurrentPath: string

proc `currentPath=`(v: FileSystemView, val:string)=
    if cmp(val, v.mCurrentPath) != 0:
        v.mCurrentPath = val
        if not v.mOnPathChanged.isNil:
            v.mOnPathChanged(v.mCurrentPath)

proc reloadFileSystem(v: FileSystemView)
proc onFilter*(v: FileSystemView, cb: proc(pathEntry: tuple[kind: PathComponent, path: string]): bool)=
    v.mFilter = cb
    v.reloadFileSystem()
    v.fileSystemTree.reloadData()
    v.contentView.reload()

proc onFilterContent*(v: FileSystemView, cb: proc(path: string): bool) =
    v.mFilterContent = cb
    v.contentView.reload()

proc onDragStart*(v: FileSystemView, cb: proc(items: seq[FilePreview]))=
    v.mOnDragStart = cb

proc onDoubleClicked*(v: FileSystemView, cb: proc(item: FilePreview))=
    v.mOnDoubleClicked = cb

proc onPathChanged*(v: FileSystemView, cb: proc(np: string))=
    v.mOnPathChanged = cb

proc `currentPathNode=`(v: FileSystemView, node: PathNode)=
    v.mCurrentPathNode = node
    v.contentView.reload()

proc directoryContent(v: FileSystemView, path: string, hashstr: var string): PathNode =
    result = new(PathNode)
    result.name = splitFile(path).name
    result.fullPath = path
    result.children = @[]

    hashstr = ""

    for kind, path in walkDir(path):
        let sp = splitFile(path)

        if sp.name.len > 0 and sp.name[0] == '.':
            continue

        if not v.mFilter.isNil and not v.mFilter((kind: kind, path: path)):
            continue

        var pathNode = new(PathNode)
        pathNode.hasContent = kind == pcDir or kind == pcLinkToDir
        pathNode.fullPath = path
        pathNode.name = sp.name
        pathNode.children = @[]
        result.children.add(pathNode)
        hashstr &= $hash(path)

    result.children.sort do(a,b: PathNode) -> int:
        result = (b.hasContent.int - a.hasContent.int)
        if result == 0:
            result = cmp(splitFile(a.fullPath).ext, splitFile(b.fullPath).ext)
        if result == 0:
            result = cmp(a.name, b.name)

    result.contentHash = hashstr

proc reloadFileSystem(v: FileSystemView)=
    v.resourceRoot = v.directoryContent(v.rootPath, v.lastFSHash)
    v.cachedResources = initTable[string, FilePreview]()
    v.lastFSReload = epochTime()

proc createDir*(v: FileSystemView)=
    createDir(v.mCurrentPath & "/new directory")

proc currentPathNodeChildren(v: FileSystemView): seq[PathNode] =
    if v.mCurrentPathNode.isNil: return
    if v.mFilterContent.isNil: return v.mCurrentPathNode.children
    for n in v.mCurrentPathNode.children:
        if v.mFilterContent(n.fullPath):
            result.add(n)
    
method init*(v: FileSystemView, r: Rect)=
    procCall v.View.init(r)

    var horLayout = newHorizontalLayout(newRect(0.0, 0.0, v.bounds.width, v.bounds.height))
    horLayout.userResizeable = true
    horLayout.resizingMask= "wh"
    horLayout.padding = 4.0
    v.mCurrentPath = ""
    v.currentPath = v.rootPath
    v.addSubview(horLayout)

    v.reloadFileSystem()

    v.fileSystemTree = OutlineView.new(newRect(0.0, 0.0, 100.0, v.bounds.height))
    v.fileSystemTree.autoresizingMask={afFlexibleWidth, afFlexibleHeight}
    var fsScroll = newScrollView(v.fileSystemTree)
    fsScroll.autoresizingMask={afFlexibleWidth, afFlexibleHeight}
    horLayout.addSubview(fsScroll)

    block setupfileSystemTree:
        v.fileSystemTree.numberOfChildrenInItem = proc(item: Variant, indexPath: openarray[int]): int =
            if indexPath.len == 0:
                return 1
            else:
                let n = item.get(PathNode)
                return n.children.len

        v.fileSystemTree.childOfItem = proc(item: Variant, indexPath: openarray[int]): Variant =
            if indexPath.len == 1:
                v.resourceRoot.outLinePath = @indexPath

                return newVariant(v.resourceRoot)
            else:
                let n = item.get(PathNode).children[indexPath[^1]]
                n.outLinePath = @indexPath
                return newVariant(n)

        v.fileSystemTree.createCell = proc(): TableViewCell =
            result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))

        v.fileSystemTree.configureCell = proc(cell: TableViewCell, indexPath: openarray[int]) =
            let n = v.fileSystemTree.itemAtIndexPath(indexPath).get(PathNode)
            let textField = TextField(cell.subviews[0])
            textField.textColor = blackColor()
            textField.text = n.name

        v.fileSystemTree.setDisplayFilter do(item: Variant)-> bool:
            var n: PathNode
            try:
                n = item.get(PathNode)
            except:
                return true
            return n.hasContent

        v.fileSystemTree.onSelectionChanged = proc() =
            v.cachedResources.clear()
            let ip = v.fileSystemTree.selectedIndexPath
            let n = if ip.len > 0:
                    v.fileSystemTree.itemAtIndexPath(ip).get(PathNode)
                else:
                    nil

            if not n.isNil:
                var hash = ""
                var newn = v.directoryContent(n.fullPath, hash)
                if n.contentHash != hash:
                    n.contentHash = hash
                    n.children = newn.children
                    v.fileSystemTree.reloadData()

            v.currentPathNode = n

        v.fileSystemTree.reloadData()

    v.contentView = newAssetContainerView(newRect(0.0, 0.0, v.bounds.width - 300.0, v.bounds.height))
    horLayout.addSubview(v.contentView)
    v.contentView.setCompact(false)
    v.contentView.numberOfItems = proc(): int =
        if not v.mCurrentPathNode.isNil:
            v.currentPath = v.mCurrentPathNode.fullPath
            return v.currentPathNodeChildren().len

    v.contentView.viewForItem = proc(i: int): View =
        let n = v.currentPathNodeChildren()[i]
        var size = v.contentView.itemSize
        var filePreview = v.cachedResources.getOrDefault(n.fullPath)

        if filePreview.isNil:
            filePreview = createFilePreview(n, newRect(0.0, 0.0, size.width, size.height), v.contentView.isCompact)
            v.cachedResources[n.fullPath] = filePreview

        if n.hasContent:
            filePreview.onDoubleClicked = proc() =
                v.fileSystemTree.selectItemAtIndexPath(n.outLinePath)

        elif filePreview.kind == akComposition:
            filePreview.onDoubleClicked = proc() =
                if not v.mOnDoubleClicked.isNil:
                    v.mOnDoubleClicked(filePreview)

        result = filePreview

    # v.contentView.onItemSelected = proc(i: int)=
    #     var fileView = v.contentView.subviews[i].FilePreview
    #     fileView.select()

    # v.contentView.onItemDeselected = proc(i: int)=
    #     if i >= 0 and i < v.contentView.subviews.len:
    #         var fileView = v.contentView.subviews[i].FilePreview
    #         fileView.deselect()

    v.contentView.onItemDoubleClick = proc(i: int)=
        let idx = i
        # setTimeout(0.1) do():
        var fileView = v.contentView.subviews[idx].FilePreview
        fileView.doubleClicked()

    v.contentView.onItemsDelete = proc(selectedItems: seq[int])=
        v.cachedResources.clear()
        var path = v.mCurrentPathNode.outLinePath
        for item in selectedItems:
            let n = v.currentPathNodeChildren()[item]
            discard tryRemoveFile(n.fullPath)

        v.reloadFileSystem()
        v.fileSystemTree.reloadData()
        v.fileSystemTree.selectItemAtIndexPath(path)

    v.contentView.onBackspace = proc()=
        var path = v.mCurrentPathNode.outLinePath
        if path.len > 1:
            path = path[0..^2]
            v.fileSystemTree.selectItemAtIndexPath(path)

    v.contentView.onItemsDragStart = proc(items: seq[int])=
        var fileViews = newSeq[FilePreview](items.len)
        var index = 0

        for i in items:
            var fileView = v.contentView.subviews[i].FilePreview
            fileViews[index] = fileView
            inc index

        if not v.mOnDragStart.isNil:
            v.mOnDragStart(fileViews)

    v.contentView.onItemRenamed = proc(item: int)=
        var fileView = v.contentView.subviews[item].FilePreview
        fileView.rename() do(name: string):
            echo "renamed ", fileView.path, " to ", name
            setTimeout(0.1) do():
                discard v.window.makeFirstResponder(v.contentView)
            # discard v.contentView.makeFirstResponder()

    v.currentPathNode=v.resourceRoot
    horLayout.setDividerPosition(300.0, 0)

proc createProjectFSView*(rootPath: string, r: Rect):FileSystemView=
    result.new()
    result.rootPath = rootPath
    result.rootName = "res://"
    result.init(r)

proc createFSView*(rootPath: string, r: Rect):FileSystemView=
    result.new()
    result.rootPath = rootPath
    result.rootName = "root"
    result.init(r)

proc reloadIfNeeded*(v: FileSystemView)=
    if true: return 
