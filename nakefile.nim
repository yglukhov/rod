import nimx.naketools
import osproc

withDir "..":
    direShell "nimble install -y"

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = false
    b.mainFile = "editor/rodedit"
    b.originalResourcePath = "editor/res"

task "tests", "Build and run autotests":
    let b = newBuilder()

    if b.platform == "js":
        b.runAfterBuild = false

    b.additionalNimFlags.add "-d:runAutoTests"
    b.build()

    if b.platform == "js":
        b.runAutotestsInFirefox()

task "docs", "Build documentation":
    withDir "./doc":
        for t, f in walkDir "../rod":
            if f.endsWith(".nim"):
                shell "nim doc2 -d:js " & f

        for t, f in walkDir ".":
            if f.endsWith(".rst"):
                direShell "nim rst2html " & f

        copyDir "../build/js", "./livedemo"
