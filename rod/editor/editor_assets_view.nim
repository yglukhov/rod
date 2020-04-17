import nimx / [types, matrixes, view, table_view_cell, text_field,
    scroll_view, button, event, linear_layout, collection_view, formatted_text, image,
    context, drag_and_drop, pasteboard / pasteboard_item, view_render_to_image,
    segmented_control ]

import file_system / [ filesystem_view ]
import variant, tables
import rod / [edit_view]
import times

type EditorAssetsView* = ref object of EditorTabView
    fileSystemView: FileSystemView

method init*(v: EditorAssetsView, r: Rect)=
    procCall v.View.init(r)

    v.fileSystemView = createProjectFSView(v.editor.currentProjectPath(), newRect(0.0, 0.0, v.bounds.width, v.bounds.height - 20.0))
    v.fileSystemView.resizingMask="wh"
    v.addSubview(v.fileSystemView)

    var bottomMenu = newView(newRect(0, v.bounds.height - 20.0, v.bounds.width, 20))
    bottomMenu.autoresizingMask = { afFlexibleWidth, afFlexibleMinY }
    v.addSubview(bottomMenu)

    var segm = SegmentedControl.new(newRect(bottomMenu.bounds.width - 150.0, 0.0, 150, 20.0))
    segm.segments = @["compact", "normal"]
    segm.autoresizingMask = { afFlexibleMinX, afFlexibleHeight }
    segm.selectedSegment = 1
    bottomMenu.addSubview(segm)
    segm.onAction do():
        v.fileSystemView.cachedResources.clear()
        v.fileSystemView.contentView.setCompact segm.selectedSegment == 0

    var curPath = newLabel(newRect(0,0,bottomMenu.bounds.width-segm.bounds.width, 20.0))
    bottomMenu.addSubview(curPath)
    v.fileSystemView.onPathChanged do(np: string):
        curPath.text = np


    v.fileSystemView.onDragStart do(fileViews: seq[FilePreview]):
        var drag_data = ""
        var drag_kind = ""

        for fileView in fileViews:
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
            img = fileViews[0].screenShot()
            startDrag(dpi, img)

    v.fileSystemView.onDoubleClicked do(item: FilePreview):
        if item.kind == akComposition:
            v.editor.openComposition(item.path)

method tabSize*(v: EditorAssetsView, bounds: Rect): Size=
    result = newSize(bounds.width, 450.0)

method tabAnchor*(v: EditorAssetsView): EditorTabAnchor =
    result = etaBottom

method update*(v: EditorAssetsView)=
    v.fileSystemView.reloadIfNeeded()

registerEditorTab("Assets", EditorAssetsView)

#[
    HELPERS
]#

