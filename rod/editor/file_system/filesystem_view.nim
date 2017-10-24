import nimx / [view, types, outline_view, linear_layout,
    scroll_view, table_view_cell, text_field, button]
import editor_asset_icon_view, editor_asset_container_view
import os, algorithm, sequtils, hashes, times, tables
import variant

export editor_asset_icon_view
export editor_asset_container_view

type FileSystemView* = ref object of View
    rootPath*: string
    contentView*: AssetContainerView
    fileSystemTree*: OutlineView
    resourceRoot*: PathNode
    mCurrentPathNode*: PathNode
    cachedResources*: Table[string, FilePreview]
    lastFSReload*: float
    lastFSHash*: string
    mOnDragStart: proc(items: seq[FilePreview])
    mOnDoubleClicked: proc(item: FilePreview)
    mOnPathChanged: proc(np: string)
    mCurrentPath: string

proc `currentPath=`(v: FileSystemView, val:string)=
    if cmp(val, v.mCurrentPath) != 0:
        v.mCurrentPath = val
        if not v.mOnPathChanged.isNil:
            v.mOnPathChanged(v.mCurrentPath)

proc onDragStart*(v: FileSystemView, cb: proc(items: seq[FilePreview]))=
    v.mOnDragStart = cb

proc onDoubleClicked*(v: FileSystemView, cb: proc(item: FilePreview))=
    v.mOnDoubleClicked = cb

proc onPathChanged*(v: FileSystemView, cb: proc(np: string))=
    v.mOnPathChanged = cb

proc `currentPathNode=`(v: FileSystemView, node: PathNode)=
    v.mCurrentPathNode = node
    v.contentView.reload()

proc buildResourceTree(path: string, hashstr: var string): PathNode=
    result = new(PathNode)
    result.name = "res://"
    result.fullPath = path

    var curPathNodes = @[result]
    var totalNodes = 0
    hashstr = ""
    while true:
        var dirs = newSeq[PathNode]()
        for curPathNode in curPathNodes:
            var children = newSeq[PathNode]()
            for kind, path in walkDir(curPathNode.fullPath):
                let sp = splitFile(path)
                if sp.name.len > 0 and sp.name[0] == '.': continue

                var pathNode = new(PathNode)
                pathNode.hasContent = kind == pcDir or kind == pcLinkToDir
                pathNode.fullPath = path
                pathNode.name = sp.name
                children.add(pathNode)
                hashstr &= $hash(path)
                inc totalNodes
                if kind != pcFile and kind != pcLinkToFile:
                    dirs.add(pathNode)

            children.sort do(a,b: PathNode) -> int:
                result = (b.hasContent.int - a.hasContent.int)
                if result == 0:
                    result = cmp(splitFile(a.fullPath).ext, splitFile(b.fullPath).ext)
                if result == 0:
                    result = cmp(a.name, b.name)

            curPathNode.children = children
            curPathNode.hasContent = children.len > 0
        curPathNodes = dirs

        if curPathNodes.len == 0: break

    hashstr &= $hash(totalNodes)

proc reloadFileSystem(v: FileSystemView)=
    v.resourceRoot = buildResourceTree(v.rootPath, v.lastFSHash)
    v.cachedResources = initTable[string, FilePreview]()
    v.lastFSReload = epochTime()

method init*(v: FileSystemView, r: Rect)=
    procCall v.View.init(r)
    var horLayout = newHorizontalLayout(newRect(0.0, 0.0, v.bounds.width, v.bounds.height))
    horLayout.userResizeable = true
    horLayout.resizingMask= "wh"
    horLayout.padding = 4.0
    v.mCurrentPath = ""
    v.addSubview(horLayout)

    v.reloadFileSystem()

    v.fileSystemTree = OutlineView.new(newRect(0.0, 0.0, 100.0, v.bounds.height))
    var fsScroll = newScrollView(v.fileSystemTree)
    fsScroll.resizingMask="wh"
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
            result = newTableViewCell(newLabel(newRect(0, 0, 300, 20)))

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

            echo "onSelectionChanged ", ip, " isnil ", n.isNil
            v.currentPathNode = n

        v.fileSystemTree.reloadData()

    v.contentView = newAssetContainerView(newRect(0.0, 0.0, v.bounds.width - 300.0, v.bounds.height))
    horLayout.addSubview(v.contentView)
    v.contentView.setCompact(false)
    v.contentView.numberOfItems = proc(): int =
        if not v.mCurrentPathNode.isNil and not v.mCurrentPathNode.children.isNil:
            v.currentPath = v.mCurrentPathNode.fullPath
            # curPath.text = v.mCurrentPathNode.fullPath #todo: normalize path here
            return v.mCurrentPathNode.children.len

    v.contentView.viewForItem = proc(i: int): View =
        let n = v.mCurrentPathNode.children[i]
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

        # elif filePreview.kind == akComposition:
        #     filePreview.onDoubleClicked = proc() =
        #         v.editor.openComposition(n.fullPath)

        result = filePreview
        # echo "end viewfor item ", i

    v.contentView.onItemSelected = proc(i: int)=
        var fileView = v.contentView.subviews[i].FilePreview
        fileView.select()

    v.contentView.onItemDeselected = proc(i: int)=
        var fileView = v.contentView.subviews[i].FilePreview
        fileView.deselect()

    v.contentView.onItemDoubleClick = proc(i: int)=
        var fileView = v.contentView.subviews[i].FilePreview
        echo "i dbc ", i,  " fp ", fileView.path
        fileView.doubleClicked()

    v.contentView.onItemsDelete = proc(selectedItems: seq[int])=
        v.cachedResources.clear()
        var path = v.mCurrentPathNode.outLinePath
        for item in selectedItems:
            let n = v.mCurrentPathNode.children[item]
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

    v.currentPathNode=v.resourceRoot
    horLayout.setDividerPosition(300.0, 0)

proc createFileSystemView*(rootPath: string, r: Rect):FileSystemView=
    result.new()
    result.rootPath = rootPath
    result.init(r)

proc reloadIfNeeded*(v: FileSystemView)=
    let ct = epochTime()
    if ct - v.lastFSReload > 15.0:
        v.lastFSReload = ct
        var hashstr = ""
        var tmpRoot = buildResourceTree(v.rootPath, hashstr)
        if hashstr != v.lastFSHash:
            echo "reload"
            var prevRoot = v.resourceRoot
            var curPath = v.mCurrentPathNode.outLinePath
            var curNode = tmpRoot
            for i, op in curPath:
                if i == 0: continue
                if op < curNode.children.len:
                    var nchild = curNode.children[op]
                    var ochild = prevRoot.children[op]
                    if nchild.name == ochild.name:
                        prevRoot = ochild
                        curNode = nchild
                        continue

                for ch in curNode.children:
                    if ch.name == prevRoot.children[op].name:
                        curNode = ch
                        prevRoot = prevRoot.children[op]
                        break

            v.lastFSHash = hashstr
            v.resourceRoot = tmpRoot
            v.cachedResources.clear()
            v.currentPathNode=curNode
            v.fileSystemTree.reloadData()

            var path = v.mCurrentPathNode.outLinePath
            if path.len > 1:
                path = path[0..^1]
                v.fileSystemTree.selectItemAtIndexPath(path)
