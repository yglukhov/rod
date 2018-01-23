import tables, logging, strutils

import nimx / [ matrixes, system_logger ]
import rod / [ viewport, edit_view, node ]
import rod.editor.editor_error_handling
import rod.component.camera

import rod.component.solid

import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.sprite
import rod.component
import rod.scene_composition

import nimx.image
import nimx.window
import nimx.autotest

import rod.editor.editor_project_settings

when loadingAndSavingAvailable:
    import rod.editor.editor_open_project_view

const isMobile = defined(ios) or defined(android)

type EditView = ref object of SceneView

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        quitApplication()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc switchToEditView(w: Window, proj: EditorProject)=
    # let editView = EditView.new(w.bounds)

    # editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    # editView.rootNode = newNode("(root)")
    # let cameraNode = editView.rootNode.newChild("camera")
    # discard cameraNode.component(Camera)
    # cameraNode.positionZ = 100

    # let light = editView.rootNode.newChild("point_light")
    # light.position = newVector3(-100,100,100)
    # let lightSource = light.component(LightSource)
    # lightSource.setDefaultLightSource()

    # w.addSubview(editView)

    var editor = w.startEditorForProject(proj)
    # editor.startEditingNodeInView(nil, w, false)

proc startApplication() =
    when isMobile or defined(js):
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))
    when loadingAndSavingAvailable:
        let settings = getEditorSettings()
        if settings.lastProject.len > 0:
            var proj = getProjectAtPath(settings.lastProject)
            mainWindow.title = "Project " & proj.name
            mainWindow.switchToEditView(proj)
        else:
            var openProjView = new(EditorOpenProjectView)
            openProjView.init(mainWindow.bounds)
            mainWindow.addSubView(openProjView)

            openProjView.onOpen = proc(p: EditorProject) =
                openProjView.removeFromSuperview()
                mainWindow.title = "Project " & p.name
                mainWindow.switchToEditView(p)
    else:
        var proj: EditorProject
        mainWindow.title = "Rod"
        mainWindow.switchToEditView(proj)

    runAutoTestsIfNeeded()

when not defined(js):
    onUnhandledException = proc(msg: string) =
        var msg = msg.indent(8)
        error "Exception caught:\n ", msg

runApplication:
    startApplication()
