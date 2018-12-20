import nimx.naketools
import osproc

beforeBuild = proc(b: Builder) =
    #b.disableClosureCompiler = true
    b.mainFile = "editor/rodedit_main"
    b.originalResourcePath = "editor/res"
    b.additionalNimFlags.add("-d:rodplugin")
    b.additionalNimFlags.add("--putenv:PREFS_FILE_NAME=rodedit.json")

proc filterExceptions(name: string): bool =
    let exc = @["main", "nakefile", "rodedit", "rodasset"]

    for e in exc:
        let fileName = e & ".nim"
        if name.contains(e):
            return false

    result = true

proc doMainModuleTests() =
    for f in walkDirRec "../rod/":
        if f.endsWith(".nim") and f.filterExceptions():
            let content = readFile(f)

            if content.contains("isMainModule"):
                direShell "nim c -r --threads:on " & f

task "mtests", "Main module tests":
    doMainModuleTests()

task "tests", "Build and run autotests":
    let b = newBuilder()

    if b.platform == "js":
        b.runAfterBuild = false

    b.additionalNimFlags.add "-d:runAutoTests"
    b.build()

    if b.platform == "js":
        b.runAutotestsInFirefox()
    doMainModuleTests()

task "docs", "Build documentation":
    createDir "./build/doc"
    withDir "./build/doc":
        for t, f in walkDir "../../rod":
            if f.endsWith(".nim"):
                shell "nim doc2 -d:js " & f & " &>/dev/null"

        for t, f in walkDir "../../doc":
            if f.endsWith(".rst"):
                direShell "nim rst2html " & f & " &>/dev/null"

        copyDir "../js", "./livedemo"
