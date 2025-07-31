import editor_types
import nimx / [ types, view, split_view, layout, text_field ]
import views / [ toolbar_view, leftpanel_view ]

type EditorView* = ref object of View
    toolBar: ToolBarView
    leftPart: LeftPanelView
    centralPart: View
    bottomPart: View
    rightPart: View


method init*(e: EditorView) =
    procCall e.View.init()

    e.makeLayout:
        backgroundColor: newColor(0.0, 0.0, 0.0, 1.0)
        - ToolBarView as toolbar:
            origin == super
            width == super
            height == 30.0

        - SplitView:
            y == 30.0
            height == super - 30.0
            width == super
            vertical: false
            resizable: true

            - LeftPanelView as leftPart:
                x == 0
                width == 250 @ WEAK
                350 >= self.width
                self.width >= 150
                height == super

            - View:
                x >= prev.x
                y == super
                height == super
                width >= 150
                backgroundColor: newColor(0.4, 0.8, 0.3, 1.0)

                - SplitView:
                    x == super
                    y == super
                    width == super
                    height == super
                    vertical: true
                    resizable: true

                    - View as centralPart:
                        y == super
                        width == super
                        backgroundColor: newColor(1.0, 0.0, 0.0, 1.0)
                        - Label:
                            text: "Middle up"
                            origin == super + 15

                    - View as bottomPart:
                        width == super
                        height == 150 @ WEAK
                        backgroundColor: newColor(0.0, 0.0, 1.0, 1.0)
                        - Label:
                            text: "Middle bottom"
                            origin == super + 15

            - View as rightPart:
                x >= prev.x
                width == 250 @ WEAK
                350 >= self.width
                self.width >= 150
                height == super
                backgroundColor: newColor(0.0, 1.0, 1.0, 1.0)

                - Label:
                    text: "Right part"
                    origin == super + 15

    e.toolBar = toolbar
    e.leftPart = leftPart
    e.centralPart = centralPart
    e.bottomPart = bottomPart
    e.rightPart = rightPart
