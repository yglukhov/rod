import nimx.naketools
import osproc

beforeBuild = proc(b: Builder) =
    b.mainFile = "main.nim"
    b.originalResourcePath = "res"
