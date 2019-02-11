import strutils, tables, logging
import nimx.view
import nimx.text_field
import nimx.button
import nimx.popup_button
import nimx.scroll_view

import variant

export view

import rod.edit_view
import rod.editor.editor_error_handling

type EditorConsole* = ref object of EditorTabView
    contentView: View

    scView: ScrollView
    currentLevel: Level

proc reloadConsole(v: EditorConsole)=
    var msgs = gEditorLogger.dump(v.currentLevel)

    while v.contentView.subviews.len > 0:
        v.contentView.subviews[0].removeFromSuperView()

    var lblText = "\n"
    for msg in msgs:
        lblText &= msg & "\n"

    var lines = max(lblText.count("\n"),1)
    # info "lines ", lines

    var lbl = newLabel(newRect(10, 10, v.contentView.bounds.width, lines.float * 20.0))
    lbl.resizingMask = "wh"
    lbl.backgroundColor = whiteColor()
    lbl.text = lblText
    # lbl.setBoundsSize(newSize(v.contentView.bounds.width, lines.float * 20.0))
    v.contentView.setFrameSize(newSize(v.contentView.bounds.width, lines.float * 20.0 + 10.0))
    v.contentView.addSubview(lbl)


method init*(v: EditorConsole, r: Rect) =
    procCall v.View.init(r)
    v.resizingMask = "wh"

    v.contentView = newView(newRect(0, 0, v.bounds.width, v.bounds.height))
    v.contentView.resizingMask = "wh"

    v.scView = newScrollView(v.contentView)
    v.scView.horizontalScrollBar = nil
    v.scView.resizingMask = "wh"
    # v.scView.setFrame(newRect(0.0, 20.0, v.bounds.width, v.bounds.height - 20.0))
    v.addSubview(v.scView)

    v.currentLevel = 0.Level
    var popupButton = PopupButton.new(newRect(v.bounds.width - 240.0, 0, 240, 20))
    popupButton.autoresizingMask = {afFlexibleMinX, afFlexibleMaxY}

    var items = newSeq[string]()
    for lvl in low(Level) .. high(Level):
        items.add($lvl)
    popupButton.items = items
    popupButton.onAction do():
        v.currentLevel = popupButton.selectedIndex.Level
        v.reloadConsole()
    v.addSubview(popupButton)

    v.reloadConsole()

method tabSize*(v: EditorConsole, bounds: Rect): Size=
    result = newSize(bounds.width, 250.0)

method tabAnchor*(v: EditorConsole): EditorTabAnchor =
    result = etaBottom

import times
const updateRate = 0.25
var lastUpdate = 0.0

method update*(v: EditorConsole)=
    let t = epochTime()
    if t - lastUpdate > updateRate:
        lastUpdate = t
        v.reloadConsole()

registerEditorTab("Console", EditorConsole)
