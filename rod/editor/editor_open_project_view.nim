import nimx / [ view, types, button, scroll_view, text_field, stack_view,
                animation, abstract_window, view_event_handling ]

import editor_project_settings
import os_files.dialog

export editor_project_settings

type EditorOpenProjectView* = ref object of View
    onOpen*: proc(p: EditorProject)
    onClose*: proc()


type EditorSaveProjectView* = ref object of View
    onSave*: proc(p: EditorProject)

var lblDefaulColor: Color

proc alertAnimationOnLabel(v: View)=
    var anim = newAnimation()
    anim.loopDuration = 0.25
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float)=
        v.backgroundColor = interpolate(newColor(1.0, 0.0, 0.0, 0.2), lblDefaulColor, p)
    v.window.addAnimation(anim)

proc createProjectView(r: Rect, proj: EditorProject, newProj: bool, onProjAction: proc(p: EditorProject)): View=
    var projView = newView(r)

    var projNameLbl = newLabel(newRect(10, 10, 80, 20))
    projNameLbl.text = "Name: "
    projView.addSubview projNameLbl

    var projPathLbl = newLabel(newRect(10, 40, 80, 20))
    projPathLbl.text = "Path: "
    projView.addSubview projPathLbl

    var projName = newTextField(newRect(90, 10, r.width - 150.0, 20))
    if not newProj:
        projName.text = proj.name
        projName.editable = false
        projName.selectable = false

    projView.addSubview projName

    var projPath = newTextField(newRect(90, 40, r.width - 150.0, 20))
    if not newProj:
        projPath.text = proj.path
        projPath.editable = false
        projPath.selectable = false

    projView.addSubview projPath

    lblDefaulColor = projPath.backgroundColor

    var chDBtn = newButton(newRect(projPath.frame.width - 40, 0, 40, 20))
    chDBtn.title = "Open"
    chDBtn.backgroundColor = grayColor()
    chDBtn.onAction do():
        var di: DialogInfo
        di.kind = dkSelectFolder
        di.title = "Choose project root directory"
        projPath.text = di.show()

    if newProj:
        projPath.addSubview(chDBtn)

    var btn = newButton(newRect(r.width - 40.0, 0.0, 40.0, 40.0))
    if newProj:
        btn.title = "Create"
        var project = proj
        btn.onAction do():

            var allowCreate = true
            if projPath.text.len == 0:
                allowCreate = false
                projPath.backgroundColor = blackColor()
                projPath.alertAnimationOnLabel()

            if projName.text.len == 0:
                allowCreate = false
                projName.alertAnimationOnLabel()

            if allowCreate:
                project.path = projPath.text
                project.name = projName.text

                project.saveProject()
                onProjAction(project)

    else:
        btn.title = "Open"
        btn.onAction do():
            onProjAction(proj)

    projView.addSubview(btn)
    result = projView
    result.backgroundColor = newColor(0.0, 0.0, 0.0, 0.2)

method init*(e: EditorOpenProjectView, r: Rect)=
    procCall e.View.init(r)

    var content = new(StackView)
    content.init r

    var scrollView = newScrollView(content)
    e.addSubview(scrollView)

    let settings = getEditorSettings()

    var closeBtn = newButton(newRect(r.width - 30.0, 0.0, 20.0, 20.0))
    closeBtn.title = "x"
    closeBtn.onAction do():
        if not e.onClose.isNil:
            e.onClose()

    content.addSubview(closeBtn)

    var projsLbl = newLabel(newRect(0, 0, r.width - 30.0, 20.0))
    projsLbl.text = "Projects:"
    content.addSubview(projsLbl)

    var newProj: EditorProject
    newProj.name = "New Project"
    newProj.path = ""
    newProj.tabs = @[(name: "Tree", frame: zeroRect), (name: "Inspector", frame: zeroRect)]

    let onOpen = proc(p: EditorProject)=
        if not e.onOpen.isNil:
            echo "open project ", p
            e.onOpen(p)

    var projView = createProjectView(newRect(0, 0, r.width - 30.0, 80), newProj, true, onOpen)

    content.addSubview(projView)

    for proj in settings.projects:
        var projView = createProjectView(newRect(0, 0, r.width - 30.0, 80), proj, false, onOpen)
        content.addSubview(projView)

method onKeyDown*(e: EditorOpenProjectView, event: var Event): bool = true
method onTouchEv*(e: EditorOpenProjectView, event: var Event): bool = true

method init*(e: EditorSaveProjectView, r: Rect)=
    procCall e.View.init(r)
    var proj: EditorProject

    var projView = createProjectView(r, proj, true) do(p: EditorProject):
        if not e.onSave.isNil:
            e.onSave(p)

    e.addSubview(projView)
