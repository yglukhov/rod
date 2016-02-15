import cligen
import imgtool
import times

proc rodimgtool(originalResPath: string = ".", resPath: string = ".", outPrefix: string = ".", nocompress: bool = false, compositions: seq[string]): int =
    var tool = newImgTool()
    tool.originalResPath = originalResPath
    tool.resPath = resPath
    tool.compositionPaths = compositions
    tool.outPrefix = outPrefix
    tool.compressOutput = not nocompress
    let startTime = epochTime()
    tool.run()
    echo "Done. Time: ", epochTime() - startTime

dispatch(rodimgtool)
