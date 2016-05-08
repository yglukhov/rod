
import nimx.naketools

withDir "..":
    direShell "nimble install -y"

beforeBuild = proc(b: Builder) =
    #b.disableClosureCompiler = true
    b.mainFile = "rodedit"
    b.additionalCompilerFlags.add "-g"
