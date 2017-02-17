import nimx.naketools
import osproc

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = true
    b.mainFile = "main"
    b.originalResourcePath = "res"
