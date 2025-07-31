import nimx / [ view, types, layout, text_field, button, formatted_text ]

type ToolBarView* = ref object of View

proc onFileClicked(v: ToolBarView) =
    echo "File Clicked"

proc onEditClicked(v: ToolBarView) =
    echo "Edit Clicked"

proc onViewClicked(v: ToolBarView) =
    echo "View Clicked"

method init*(v: ToolBarView) =
    procCall v.View.init()

    v.makeLayout:
        backgroundColor: newColor(1.0, 1.0, 0.7, 1.0)
        - Button:
            width >= 100
            y == super
            height == super
            x == super
            title: "File"
            onAction:
                v.onFileClicked()

        - Button:
            width >= 100
            y == prev.y
            height == super
            x == prev.trailing
            title: "Edit"
            onAction:
                v.onEditClicked()

        - Button:
            width >= 100
            y == prev.y
            height == super
            x == prev.trailing
            title: "View"
            onAction:
                v.onViewClicked()

        - Label:
            y == super
            height == super
            # 250 >= self.width
            text: "version: 135"
            width >= 150
            trailing == super.width
            backgroundColor: newColor(0.8, 1.0, 0.66, 1.0)
            horizontalAlignment: haCenter
            # origin == super + 15
