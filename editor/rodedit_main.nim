import std/[tables, logging, strutils]

import nimx / [ matrixes, window, autotest, layout ]
# import rod / [ edit_view ]
import ../rod/component/ all_components
import ../rod / editor / [ editor_view, editor_view_types, editor_error_handling, editor_project_settings]
import ../rod / editor / editor


const rodPluginFile {.strdefine.} = ""
when rodPluginFile.len != 0:
    import macros
    macro doImport(): untyped =
        newTree(nnkImportStmt, newLit(rodPluginFile))
    doImport()

when defined(rodedit):
    import os

when defined(debug):
    echo "Running rodedit in DEBUG"

const isMobile = defined(ios) or defined(android)

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        quitApplication()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc switchToEditView(w: Window, proj: EditorProject) =
    w.makeLayout:
        title: "Project " & proj.name

        - EditorView as editView:
            origin == super
            size == super
    # discard w.startEditorForProject(proj)

proc startApplication() =
    when isMobile or defined(js):
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(140, 40, 1600, 1000))

    var proj: EditorProject
    when loadingAndSavingAvailable:
        when defined(rodedit):
            proj.name = getAppDir().lastPathPart
            proj.path = getAppDir()
            mainWindow.title = "Project " & proj.name
    else:
        mainWindow.title = "Rod"

    let editor = createEditor(mainWindow, proj)

    runAutoTestsIfNeeded()

# when defined(rodedit):
#     onUnhandledException = proc(msg: string) {.gcsafe.} =
#         var msg = msg.indent(8)
#         error "Exception caught:\n ", msg

runApplication:
    startApplication()
