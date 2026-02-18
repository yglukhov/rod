import nimx/[view, layout, app, scroll_view, table_view, text_field, autotest, window]
import ./src/game/example_scene

const isMobile = defined(ios) or defined(android)

proc startApplication() =
    let wndRect = newRect(40, 40, 1280, 720)

    var mainWindow : Window
    when isMobile:
        mainWindow = newFullscreenWindow()
    else:
        mainWindow = newWindow(wndRect)

    mainWindow.makeLayout:
        title: "Template"
        - ExampleScene as exampleView:
            origin == super
            size == super

runApplication:
    startApplication()
