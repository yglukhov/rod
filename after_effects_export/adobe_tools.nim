# Definitions according to Adobe JAVASCRIPT TOOLS GUIDE

type
    File* = ref FileObj
    FileObj {.importc.} = object of RootObj
        name*: cstring
        path*: cstring
        encoding*: cstring
        lineFeed*: cstring # lfWindows, lfUnix or lfMacintosh
        parent*: Folder

    Folder* = ref FolderObj
    FolderObj {.importc.} = object of RootObj
        name*: cstring
        exists*: bool

const lfWindows*: cstring = "Windows"
const lfUnix*: cstring = "Unix"
const lfMacintosh*: cstring = "Macintosh"

proc newFile*(path: cstring): File {.importc: "new File".}
proc open*(f: File, mode: cstring) {.importcpp.}
template openForWriting*(f: File) = f.open("w")
proc write*(f: File, content: cstring) {.importcpp.}
proc close*(f: File) {.importcpp.}
proc copy*(src, target: File): bool {.importcpp.}
proc copy*(src: File, targetPath: cstring): bool {.importcpp.}

proc newFolder*(path: cstring): Folder {.importc: "new Folder".}
proc getFiles*(f: Folder): seq[File] {.importcpp.}
proc create*(f: Folder): bool {.importcpp.}
proc execute*(f: Folder): bool {.importcpp.}
proc remove*(f: Folder): bool {.importcpp.}
