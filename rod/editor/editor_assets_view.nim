import nimx / [outline_view, types, matrixes, view, table_view_cell, text_field,
    scroll_view, button, event, linear_layout, collection_view, formatted_text, image,
    context, drag_and_drop, pasteboard / pasteboard_item, view_render_to_image,
    segmented_control ]

import editor_asset_icon_view, editor_asset_container_view
import variant, strutils, tables
import rod / [node, rod_types, edit_view]
import os, algorithm, sequtils, times, hashes

type EditorAssetsView* = ref object of EditorTabView
    contentView: AssetContainerView
    fileSystemView: OutlineView
    resourceRoot: PathNode
    mCurrentPathNode: PathNode
    cachedResources: Table[string, FilePreview]
    lastFSReload: float
    lastFSHash: string

proc `currentPathNode=`(v: EditorAssetsView, node: PathNode)=
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

proc reloadFileSystem(v: EditorAssetsView)=
    v.resourceRoot = buildResourceTree(v.editor.currentProject.path, v.lastFSHash)
    v.cachedResources = initTable[string, FilePreview]()
    v.lastFSReload = epochTime()

method init*(v: EditorAssetsView, r: Rect)=
    procCall v.View.init(r)

    var horLayout = newHorizontalLayout(newRect(0.0, 0.0, v.bounds.width, v.bounds.height - 20.0))
    horLayout.userResizeable = true
    horLayout.resizingMask= "wh"
    horLayout.padding = 4.0

    v.addSubview(horLayout)

    v.reloadFileSystem()

    v.fileSystemView = OutlineView.new(newRect(0.0, 0.0, 100.0, v.bounds.height))
    var fsScroll = newScrollView(v.fileSystemView)
    fsScroll.resizingMask="wh"
    horLayout.addSubview(fsScroll)

    block setupFileSystemView:
        v.fileSystemView.numberOfChildrenInItem = proc(item: Variant, indexPath: openarray[int]): int =
            if indexPath.len == 0:
                return 1
            else:
                let n = item.get(PathNode)
                return n.children.len

        v.fileSystemView.childOfItem = proc(item: Variant, indexPath: openarray[int]): Variant =
            if indexPath.len == 1:
                v.resourceRoot.outLinePath = @indexPath

                return newVariant(v.resourceRoot)
            else:
                let n = item.get(PathNode).children[indexPath[^1]]
                n.outLinePath = @indexPath
                return newVariant(n)

        v.fileSystemView.createCell = proc(): TableViewCell =
            result = newTableViewCell(newLabel(newRect(0, 0, 300, 20)))

        v.fileSystemView.configureCell = proc(cell: TableViewCell, indexPath: openarray[int]) =
            let n = v.fileSystemView.itemAtIndexPath(indexPath).get(PathNode)
            let textField = TextField(cell.subviews[0])
            textField.textColor = blackColor()
            textField.text = n.name

        v.fileSystemView.setDisplayFilter do(item: Variant)-> bool:
            var n: PathNode
            try:
                n = item.get(PathNode)
            except:
                return true
            return n.hasContent

        v.fileSystemView.onSelectionChanged = proc() =
            v.cachedResources.clear()

            let ip = v.fileSystemView.selectedIndexPath
            let n = if ip.len > 0:
                    v.fileSystemView.itemAtIndexPath(ip).get(PathNode)
                else:
                    nil

            v.currentPathNode = n

        v.fileSystemView.reloadData()

    v.contentView = newAssetContainerView(newRect(0.0, 0.0, v.bounds.width - 300.0, v.bounds.height - 20.0))
    v.contentView.setCompact(false)
    horLayout.addSubview(v.contentView)

    var bottomMenu = newView(newRect(0, v.bounds.height - 20.0, v.bounds.width, 20))
    bottomMenu.autoresizingMask = { afFlexibleWidth, afFlexibleMinY }
    v.addSubview(bottomMenu)

    var segm = SegmentedControl.new(newRect(bottomMenu.bounds.width - 150.0, 0.0, 150, 20.0))
    segm.segments = @["compact", "normal"]
    segm.autoresizingMask = { afFlexibleMinX, afFlexibleHeight }
    segm.selectedSegment = 1
    bottomMenu.addSubview(segm)
    segm.onAction do():
        v.cachedResources.clear()
        v.contentView.setCompact segm.selectedSegment == 0

    var curPath = newLabel(newRect(0,0,bottomMenu.bounds.width-segm.bounds.width, 20.0))
    bottomMenu.addSubview(curPath)

    block setupContentView:
        v.contentView.numberOfItems = proc(): int =
            if not v.mCurrentPathNode.isNil and not v.mCurrentPathNode.children.isNil:
                curPath.text = v.mCurrentPathNode.fullPath #todo: normalize path here
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
                    v.fileSystemView.selectItemAtIndexPath(n.outLinePath)
            elif filePreview.kind == akComposition:
                filePreview.onDoubleClicked = proc() =
                    v.editor.openComposition(n.fullPath)

            result = filePreview

        v.contentView.onItemSelected = proc(i: int)=
            let n = v.mCurrentPathNode.children[i]
            var fileView = v.contentView.subviews[i].FilePreview
            fileView.select()

        v.contentView.onItemDeselected = proc(i: int)=
            var fileView = v.contentView.subviews[i].FilePreview
            fileView.deselect()

        v.contentView.onItemDoubleClick = proc(i: int)=
            let n = v.mCurrentPathNode.children[i]
            var fileView = v.contentView.subviews[i].FilePreview
            fileView.doubleClicked()

        v.contentView.onItemsDelete = proc(selectedItems: seq[int])=
            v.cachedResources.clear()
            var path = v.mCurrentPathNode.outLinePath
            for item in selectedItems:
                let n = v.mCurrentPathNode.children[item]
                discard tryRemoveFile(n.fullPath)

            v.reloadFileSystem()
            v.fileSystemView.reloadData()
            v.fileSystemView.selectItemAtIndexPath(path)

        v.contentView.onBackspace = proc()=
            var path = v.mCurrentPathNode.outLinePath
            if path.len > 1:
                path = path[0..^2]
                v.fileSystemView.selectItemAtIndexPath(path)

        v.contentView.onItemsDragStart = proc(items: seq[int])=
            var drag_data = ""
            var drag_kind = ""

            for i in items:
                let n = v.mCurrentPathNode.children[i]
                var fileView = v.contentView.subviews[i].FilePreview
                var pbk = ""

                if fileView.kind == akComposition:
                    pbk = rodPbComposition
                elif fileView.kind == akImage:
                    pbk = rodPbSprite

                if pbk.len > 0:
                    if drag_kind.len > 0:
                        drag_kind = rodPbFiles
                        drag_data &= ":" & fileView.path
                    else:
                        drag_kind = pbk
                        drag_data = fileView.path

            if drag_data.len > 0 and drag_kind.len > 0:
                var dpi = newPasteboardItem(drag_kind, drag_data)
                var img: Image = nil
                # if items.len > 0:
                if items.len == 1:
                    var cv = v.contentView.subviews[items[0]]
                    img = v.contentView.subviews[items[0]].screenShot()
                    # else:
                    #     var views = newSeq[View]()
                    #     for i in items:
                    #         views.add(v.contentView.subviews[i])
                    #     img = screenShot(views)
                startDrag(dpi, img)

    v.currentPathNode=v.resourceRoot
    horLayout.setDividerPosition(300.0, 0)

method tabSize*(v: EditorAssetsView, bounds: Rect): Size=
    result = newSize(bounds.width, 250.0)

method tabAnchor*(v: EditorAssetsView): EditorTabAnchor =
    result = etaBottom

method update*(v: EditorAssetsView)=
    let ct = epochTime()
    if ct - v.lastFSReload > 15.0:
        v.lastFSReload = ct
        var hashstr = ""
        var tmpRoot = buildResourceTree(v.editor.currentProject.path, hashstr)
        if hashstr != v.lastFSHash:
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
            v.fileSystemView.reloadData()

            var path = v.mCurrentPathNode.outLinePath
            if path.len > 1:
                path = path[0..^1]
                v.fileSystemView.selectItemAtIndexPath(path)


registerEditorTab("Assets", EditorAssetsView)

#[
    HELPERS
]#

