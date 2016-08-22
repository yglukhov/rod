import json, strutils
import nimx.image, nimx.types, nimx.system_logger

proc deserializeImage*(j: JsonNode): Image =
    if j.isNil:
        discard
    elif j.kind == JString:
        let name = j.getStr()
        if name.endsWith(".sspart"):
            let parts1 = name.split(" - ")
            let parts = parts1[1].split('.')
            let rect = newRect(parts[^5].parseFloat(), parts[^4].parseFloat(), parts[^3].parseFloat(), parts[^2].parseFloat())
            let realName = parts1[0]
            let ss = imageWithResource(realName)
            result = ss.subimageWithRect(rect)
            logi "WARNING: sspart images are deprecated"
        else:
            result = imageWithResource(name)
    else:
        let realName = j["file"].getStr()
        let uv = j["tex"]
        let sz = j["size"]
        let ss = imageWithResource(realName)
        result = ss.subimageWithTexCoords(
                        newSize(sz[0].getFNum(), sz[1].getFNum()),
                        [uv[0].getFNum().float32, uv[1].getFNum(), uv[2].getFNum(), uv[3].getFNum()]
                        )
