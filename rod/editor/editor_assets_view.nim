import nimx / [outline_view, types, matrixes, view, table_view_cell, text_field,
    scroll_view, button, event, linear_layout, collection_view, formatted_text, image,
    context]

import rod.edit_view
import variant, strutils, tables
import rod / [node, rod_types]
import os

type PathNode = ref object
    children: seq[PathNode]
    name: string
    fullPath: string
    hasContent: bool
    outLinePath: seq[int]

type EditorAssetsView* = ref object of EditorTabView
    contentView: CollectionView
    fileSystemView: OutlineView
    resourceRoot: PathNode
    mCurrentPathNode: PathNode

proc getProjectDir():string = getAppDir() & "/../../" # exit from build/{platform}

proc `currentPathNode=`(v: EditorAssetsView, node: PathNode)=
    v.mCurrentPathNode = node
    v.contentView.updateLayout()

proc reloadFileSystem(v: EditorAssetsView)=
    v.resourceRoot = new(PathNode)
    v.resourceRoot.name = "res://"
    v.resourceRoot.fullPath = getProjectDir()

    var curPathNodes = @[v.resourceRoot]
    var totalNodes = 0
    while true:
        var dirs = newSeq[PathNode]()
        for curPathNode in curPathNodes:
            var children = newSeq[PathNode]()
            for kind, path in walkDir(curPathNode.fullPath):
                var pathNode = new(PathNode)
                pathNode.hasContent = kind == pcDir or kind == pcLinkToDir
                pathNode.fullPath = path
                pathNode.name = splitFile(path).name
                children.add(pathNode)
                inc totalNodes
                if kind != pcFile and kind != pcLinkToFile:
                    dirs.add(pathNode)

            curPathNode.children = children
            curPathNode.hasContent = children.len > 0
        curPathNodes = dirs

        if curPathNodes.len == 0: break
    echo "reloadFileSystem total pathNodes: ", totalNodes

method init*(v: EditorAssetsView, r: Rect)=
    procCall v.View.init(r)

    var horLayout = newHorizontalLayout(newRect(0.0, 0.0, v.bounds.width, v.bounds.height))
    horLayout.userResizeable = true
    horLayout.resizingMask= "wh"
    horLayout.padding = 4.0
    
    v.addSubview(horLayout)

    v.reloadFileSystem()

    v.fileSystemView = OutlineView.new(newRect(0.0, 0.0, 300.0, v.bounds.height))
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
            let ip = v.fileSystemView.selectedIndexPath
            let n = if ip.len > 0:
                    v.fileSystemView.itemAtIndexPath(ip).get(PathNode)
                else:
                    nil

            v.currentPathNode = n
            
        v.fileSystemView.reloadData()                

    v.contentView = newCollectionView(newRect(0.0, 0.0, v.bounds.width - 300.0, v.bounds.height), newSize(150, 150), LayoutDirection.TopDown)
    horLayout.addSubview(v.contentView)

    block setupContentView:
        v.contentView.numberOfItems = proc(): int =
            if not v.mCurrentPathNode.isNil and not v.mCurrentPathNode.children.isNil:
                return v.mCurrentPathNode.children.len

        v.contentView.viewForItem = proc(i: int): View =
            let n = v.mCurrentPathNode.children[i]
            let spFile = splitFile(n.fullPath)

            var size = v.contentView.itemSize

            if n.hasContent:
                var openContentBtn = newButton(newRect(0.0, 0.0, size.width, size.height))
                openContentBtn.onAction do():
                    v.fileSystemView.selectItemAtIndexPath(n.outLinePath)
                result = openContentBtn
                # result.backgroundColor = newColor(0.2, 0.2, 0.2, 0.4)
            # elif spFile.ext == ".png":
            #     var img = imageWithContentsOfFile(n.fullPath)
            #     var imgView = newImagePreview(newRect(0.0, 0.0, size.width, size.height), img)
            #     result = imgView
            else:
                result = newView(newRect(0.0, 0.0, size.width, size.height))        
                result.backgroundColor = newColor(0.2, 0.2, 0.2, 0.4)

            var nameLbl = newLabel(newRect(0.0, size.height - 20.0, size.width, 20.0))
            nameLbl.formattedText.horizontalAlignment = haCenter
            nameLbl.text = n.name & spFile.ext
            result.addSubview(nameLbl)

            
            
        v.contentView.itemSize = newSize(150.0, 100.0)
        v.contentView.layoutWidth = 0
        v.contentView.offset = 5.0

    v.currentPathNode=v.resourceRoot
    horLayout.setDividerPosition(300.0, 0)

method tabSize*(v: EditorAssetsView, bounds: Rect): Size=
    result = newSize(bounds.width, 250.0)

method tabAnchor*(v: EditorAssetsView): EditorTabAnchor =
    result = etaBottom


registerEditorTab("Assets", EditorAssetsView)

#[
    HELPERS
]#

