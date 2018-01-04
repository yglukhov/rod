import logging, tables, strutils, times

type EditorLogger* = ref object of Logger
    msgDump*: TableRef[Level, seq[string]]

method log*(logger: EditorLogger, level: Level, args: varargs[string,`$`])=
    var t = "[" & getClockStr() & "] "
    var msg = ""
    for arg in args:
        msg &= arg

    var msgseq = msg.split("\n")

    if msgseq.len > 1:
        msg = ""
        for i, m in msgseq:
            msg &= (if i < msgseq.len - 1: "\n" else: "") & t & m
    else:
        msg = t & msg

    if logger.msgDump.isNil:
        logger.msgDump = newTable[Level, seq[string]]()

    var dump = logger.msgDump.getOrDefault(level)
    if dump.isNil:
        dump = @[]

    dump.add(msg)
    logger.msgDump[level] = dump

proc clear*(logger: EditorLogger, level: Level)=
    var dump = logger.msgDump.getOrDefault(level)
    if not dump.isNil:
        dump.setLen(0)
    logger.msgDump[level] = dump

proc clearAll*(logger: EditorLogger)=
    for level in low(Level) .. high(Level):
        logger.clear(level)

proc dump*(logger: EditorLogger, level: Level):seq[string]=
    result = @[]
    if logger.msgDump.isNil: return
    if level == lvlAll:
        for k, v in logger.msgDump:
            result.add(v)
    else:
        var dump = logger.msgDump.getOrDefault(level)
        if not dump.isNil:
            result.add(dump)

var gEditorLogger* = new(EditorLogger)

addHandler(gEditorLogger)
