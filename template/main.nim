import nimx/[view, app, scroll_view, table_view, text_field, autotest, window]
import src/game/example_scene

const isMobile = defined(ios) or defined(android)

let wndRect = newRect(40, 40, 1280, 720)
proc startApplication() =
    var mainWindow : Window

    when isMobile:
        mainWindow = newFullscreenWindow()
    else:
        mainWindow = newWindow(wndRect)

    mainWindow.title = "Template"

    let gs = new(ExampleScene)
    gs.init(mainWindow.bounds)
    gs.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    mainWindow.addSubview(gs)

    gs.setFrame(mainWindow.bounds)
    gs.resizeSubviews(mainWindow.bounds.size)

runApplication:
    startApplication()
