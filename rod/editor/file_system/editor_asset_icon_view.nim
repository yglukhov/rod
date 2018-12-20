import nimx / [ text_field, image, view, formatted_text, context, button,
                render_to_image, window, panel_view, image_preview,
                view_event_handling ]
import nimx.assets.asset_loading
import tables, os, streams
when not defined(android) and not defined(ios) and not defined(emscripten):
    import os_files.file_info

type PathNode* = ref object of RootObj
    children*: seq[PathNode]
    name*: string
    contentHash*: string
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
filesExtensions[".jcomp"] = akComposition

type ImageIconView* = ref object of View
    image: Image
    isThumb: bool
    makeThumb: bool

type FilePreview* = ref object of View
    path*: string
    # pathNode*: PathNode
    nameField*: TextField
    icon*: View
    selectionView: View
    onDoubleClicked*: proc()
    isCompact*: bool

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

proc createFilePreview*(p: PathNode, r: Rect, compact: bool): FilePreview =
    result.new()
    result.init(r)
    result.path = p.fullPath
    # result.pathNode = p
    result.isCompact = compact

    let sp = result.path.splitFile()
    if p.hasContent:
        result.kind = akContainer
    else:
        result.kind = filesExtensions.getOrDefault(sp.ext)

    const icoset = 25.0

    var iconSize = newSize(min(r.width, r.height) - icoset, min(r.width, r.height) - icoset)
    var iconPos = newPoint(icoset * 0.5, 0.0)
    if compact:
        iconPos.x = 0.0
        iconSize = newSize(r.height, r.height)

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
        let img_data = iconBitmapForFile(p.fullPath, 128, 128)
        if not img_data.isNil:
            let img = imageWithBitmap(cast[ptr uint8](img_data), 128, 128, 4)
            let imgView = new(ImageIconView)
            imgView.init(newRect(iconPos, iconSize))
            imgView.makeThumb = true
            imgView.image = img
            res.icon = imgView
        else:
            res.icon = newView(newRect(iconPos, iconSize))
            res.icon.backgroundColor = newColor(0.5, 0.4, 0.6, 1.0)

    of akComposition:
        res.icon = newView(newRect(iconPos, iconSize))
        res.icon.backgroundColor = newColor(0.5, 0.8, 0.6, 1.0)

    else:
        let img_data = iconBitmapForFile(p.fullPath, 128, 128)
        if not img_data.isNil:
            let img = imageWithBitmap(cast[ptr uint8](img_data), 128, 128, 4)
            let imgView = new(ImageIconView)
            imgView.init(newRect(iconPos, iconSize))
            imgView.makeThumb = true
            imgView.image = img
            res.icon = imgView
        else:
            res.icon = newView(newRect(iconPos, iconSize))
            res.icon.backgroundColor = newColor(0.5, 0.5, 0.5, 0.2)
            var extField = newLabel(newRect(0.0, 0.0, iconSize.width, iconSize.height))
            extField.formattedText.horizontalAlignment = haCenter
            extField.formattedText.verticalAlignment = vaCenter
            extField.formattedText.truncationBehavior = tbCut
            extField.text = sp.ext[1..^1]
            extField.formattedText.boundingSize = extField.bounds.size

            res.icon.addSubview(extField)

    res.addSubview(res.icon)
    var textFrame = newRect(0.0, r.size.height - 20.0, r.size.width, 20.0)
    var valig = vaTop
    var holig = haCenter
    if res.isCompact:
        textFrame.origin.y = 0.0
        textFrame.origin.x = iconSize.width
        textFrame.size.height = r.size.height
        textFrame.size.width = r.size.width - textFrame.origin.x
        valig = vaCenter
        holig = haLeft

    res.nameField = newLabel(textFrame)
    if res.isCompact:
        res.nameField.backgroundColor = newColor(0.0, 0.2, 0.3, 0.3)
    res.nameField.formattedText.horizontalAlignment = holig
    res.nameField.formattedText.verticalAlignment = valig
    res.nameField.formattedText.truncationBehavior = tbEllipsis
    res.nameField.formattedText.boundingSize = newSize(textFrame.size.width, textFrame.size.height)
    res.nameField.text = sp.name & sp.ext

    res.addSubview(res.nameField)

proc doubleClicked*(v: FilePreview)=
    if not v.onDoubleClicked.isNil:
        v.onDoubleClicked()
    else:
        openInDefaultApp(v.path)

proc rename*(v: FilePreview, cb:proc(name: string))=
    if not v.selectionView.isNil:
        discard v.window.makeFirstResponder(v.selectionView)
        let tf = v.selectionView.TextField
        let col = tf.backgroundColor
        tf.editable = true
        tf.onAction do():
            if tf.text.len > 0:
                tf.editable=false
                tf.backgroundColor = col
                tf.onAction(nil)
                if tf.text != v.nameField.text:
                    cb(tf.text)

proc select*(v: FilePreview)=
    if not v.selectionView.isNil:
        v.selectionView.removeFromSuperview()
        v.selectionView = nil

    let sp = splitFile(v.path)
    var orig = v.nameField.frame.origin
    let width = max(v.nameField.formattedText.totalWidth() + 15.0, v.nameField.bounds.width)
    let height = max(v.nameField.formattedText.totalHeight() + 15.0, v.nameField.bounds.height)
    orig = newPoint(orig.x, orig.y)
    if not v.isCompact:
        orig.x -= width * 0.5

    var fullName = newLabel(newRect(orig, newSize(width, height)))
    fullName.backgroundColor = newColor(0.7, 0.7, 1.0, 1.0)
    fullName.text = sp.name & sp.ext

    v.addSubview(fullName)
    v.selectionView = fullName

proc deselect*(v: FilePreview)=
    if not v.selectionView.isNil:
        v.selectionView.removeFromSuperview()
        v.selectionView = nil
