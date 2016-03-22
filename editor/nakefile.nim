
import nimx.naketools

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = true

    if b.platform == "android":
        b.additionalLinkerFlags.add(["-lGLESv3", "-lOpenSLES"])
        b.additionalCompilerFlags.add("-g")
        b.targetArchitectures = @["armeabi"]
        b.androidPermissions.add("INTERNET")
        b.screenOrientation = "sensorLandscape"

