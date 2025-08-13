import variant
import std / [sets, intsets, algorithm, os]
import nimx / [ outline_view, text_field, view, button, layout, types, table_view_cell, scroll_view ]
import ../editor_view_types
import ./path_node

type
  EditorAssetsTreeView* = ref object of View
    outlineView: OutlineView
    filterField: TextField
    dontNotifySelection: bool
    rootNode: PathNode
    mOnSelectCb: proc(p: PathNode) {.gcsafe.}

proc `onSelectionChanged=`*(v: EditorAssetsTreeView, cb: proc(p: PathNode) {.gcsafe.}) =
  v.mOnSelectCb = cb

method init*(v: EditorAssetsTreeView) =
  procCall v.View.init()

  v.makeLayout:
    - ScrollView:
      top == super
      leading == super
      trailing == super
      # backgroundColor: blackColor()
      - OutlineView as outline:
        # backgroundColor: grayColor()
        width == super
        height == super @ WEAK
        defaultRowHeight: 20

        numberOfChildren do(i: PathNode, indexPath: IndexPath) -> int:
          sandbox:
            result =  i.directories.len

        rootItem do() -> PathNode:
          sandbox:
            result = v.rootNode

        childOfItem do(i: PathNode, indexPath: IndexPath) -> PathNode:
          sandbox:
            result = i.directories[indexPath[^1]]

        createCell do() -> TableViewCell:
          result = newTableViewCell()
          result.makeLayout:
            - Label:
              frame == super

        configureCell do(n: PathNode, c: TableViewCell):
          let l = Label(c.subviews[0])
          let s = n.name
          l.text = s

        onSelectionChange do():
          sandbox:
            echo "EditorAssetsTreeView: selection changed ", v.outlineView.selectedIndexPath
            var node = v.rootNode
            for idx, el in v.outlineView.selectedIndexPath:
              node = node.directories[el]
            if not v.mOnSelectCb.isNil:
              v.mOnSelectCb(node)

  v.outlineView = outline
  v.rootNode = newRootPathNode(getCurrentDir())
  # v.rootNode = newRootPathNode("/Users/bro/devel")
  v.outlineView.reloadData()
