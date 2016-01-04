
proc commonSetup() =
    --threads:on
    --noMain
    #switch("warning[LockLevel]", "off")

task tests, "Autotests":
    commonSetup()
    --d:runAutoTests
    setCommand "c", "editor/rodedit"

task editor, "Editor":
    commonSetup()
    setCommand "c", "editor/rodedit"
