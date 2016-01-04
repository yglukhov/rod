
proc commonSetup() =
    --threads:on
    --noMain

task tests, "Autotests":
    commonSetup()
    --d:runAutoTests
    setCommand "c", "editor/rodedit"
