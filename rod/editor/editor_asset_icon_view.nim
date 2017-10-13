import nimx / [ text_field, image, view, formatted_text, context, button, render_to_image, window, panel_view, image_preview ]
import nimx.assets.asset_loading
import tables, os, streams
import nimx.event
import nimx.view_event_handling_new


type PathNode* = ref object
    children*: seq[PathNode]
    name*: string
    fullPath*: string
    hasContent*: bool
    outLinePath*: seq[int]

type AssetKind* = enum
    akUnknown
    akContainer # directory or supported file with content
    akImage
    akSound
    akText
    akComposition

var filesExtensions = newTable[string, AssetKind]()

filesExtensions[".png"] = akImage
filesExtensions[".jpg"] = akImage
filesExtensions[".txt"] = akText
filesExtensions[".json"] = akComposition
filesExtensions[".mp3"] = akSound
filesExtensions[".ogg"] = akSound

type ImageIconView* = ref object of View
    image: Image
    isThumb: bool
    makeThumb: bool

type FilePreview* = ref object of View
    path*: string
    nameField*: TextField
    icon*: View
    selectionView: View
    onDoubleClicked*: proc()

    case kind*: AssetKind
    of akSound:
        sound*: string
    of akText:
        data*: string
    else:
        discard

method draw*(v: ImageIconView, r: Rect)=
    procCall v.View.draw(r)
    let c = currentContext()
    if not v.image.isNil:
        if v.makeThumb:
            if not v.isThumb:
                var size = v.image.size
                var maxSize = max(size.width, size.height)
                let scale = r.width / maxSize
                if scale > 1.0:
                    v.makeThumb = false
                    v.isThumb = true
                    return
                var tsize = newSize(size.width * scale,  size.height * scale)

                var renderRect = newRect(r.origin, tsize)
                var nimg = imageWithSize(tsize)
                nimg.draw do():
                    c.drawImage(v.image, renderRect)

                v.image = nimg
                v.isThumb = true
                v.makeThumb = false
        else:
            var orig = newPoint(r.x + (r.width - v.image.size.width) * 0.5, r.y + (r.height - v.image.size.height) * 0.5)
            c.drawImage(v.image, newRect(orig, v.image.size))

proc createFilePreview*(p: PathNode, r: Rect): FilePreview =
    result.new()
    result.init(r)
    result.path = p.fullPath

    let sp = result.path.splitFile()
    if p.hasContent:
        result.kind = akContainer
    else:
        result.kind = filesExtensions.getOrDefault(sp.ext)

    const icoset = 25.0

    let iconSize = newSize(min(r.width, r.height) - icoset, min(r.width, r.height) - icoset)
    let iconPos = newPoint(icoset * 0.5, 0.0)

    let res = result
    case res.kind:
    of akSound:
        res.icon = newView(newRect(iconPos, iconSize))
        res.icon.backgroundColor = newColor(0.2, 0.3, 0.4, 1.0)

    of akImage:
        let imgView = new(ImageIconView)
        imgView.init(newRect(iconPos, iconSize))
        imgView.makeThumb = true
        loadAsset[Image]("file://" & p.fullPath) do(i: Image, err: string):
            imgView.image = i
        res.icon = imgView

    of akContainer:
        res.icon = newView(newRect(iconPos, iconSize))
        res.icon.backgroundColor = newColor(0.5, 0.4, 0.6, 1.0)

    of akComposition:
        res.icon = newView(newRect(iconPos, iconSize))
        res.icon.backgroundColor = newColor(0.5, 0.8, 0.6, 1.0)

    else:
        res.icon = newView(newRect(iconPos, iconSize))
        res.icon.backgroundColor = newColor(0.5, 0.5, 0.5, 0.2)
        var extField = newLabel(newRect(0.0, iconSize.height * 0.5 - 10.0, iconSize.width, 20.0))
        extField.formattedText.horizontalAlignment = haCenter
        extField.text = "<" & sp.ext[1..^1] & ">"

        res.icon.addSubview(extField)

    res.addSubview(res.icon)

    res.nameField = newLabel(newRect(0.0, r.size.height - 20.0, r.size.width, 20.0))
    # res.nameField.backgroundColor = newColor(0.0, 0.2, 0.3, 0.3)
    res.nameField.formattedText.horizontalAlignment = haCenter
    res.nameField.formattedText.verticalAlignment = vaTop
    res.nameField.formattedText.truncationBehavior = tbEllipsis
    res.nameField.formattedText.boundingSize = newSize(r.size.width - 40.0, 20.0)
    res.nameField.text = sp.name & sp.ext

    res.addSubview(res.nameField)

proc doubleClicked*(v: FilePreview)=
    if not v.onDoubleClicked.isNil:
        v.onDoubleClicked()
    else:
        case v.kind:

        of akImage:
            loadAsset[Image]("file://" & v.path) do(i: Image, err: string):
                var imgpreview = newImagePreview(newRect(0.0, 0.0, 0.0, 0.0), i)
                imgpreview.popupAtPoint(v.window, v.frame.origin)
        else:
            echo "double clicked ", v.kind, " path ", v.path

proc select*(v: FilePreview)=
    discard
    # var textSize = sizeOfString()
    # let sp = splitFile(v.path)

    # var fullName = newLabel(newRect(0.0, v.bounds.height - 20.0, v.bounds.width, 20.0))
    # fullName.text = sp.name & sp.ext

    # let size = fullName.textSize
    # fullName.setFrame(newRect(newPoint(-(size.width - v.bounds.width)*0.5, v.bounds.height - 20.0), size))

    # fullName.backgroundColor = newColor(1.0, 1.0, 1.0, 1.0)

    # v.addSubview(fullName)
    # v.selectionView = fullName

proc deselect*(v: FilePreview)=
    if not v.selectionView.isNil:
        v.selectionView.removeFromSuperview()
