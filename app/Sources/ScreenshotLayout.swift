import AppKit

struct ScreenshotPlacement {
    let background: CGRect
    let image: CGRect
    let toolbar: CGRect
    let parameters: CGRect?
}

enum ScreenshotLayout {
    static func make(capture: CGSize, region: CGRect, viewport: CGSize, toolbar: CGSize, parameters: CGSize,allowsOutsideRegion:Bool=false) -> ScreenshotPlacement? {
        let values=[capture.width,capture.height,region.minX,region.minY,region.width,region.height,viewport.width,viewport.height,toolbar.width,toolbar.height,parameters.width,parameters.height]
        guard values.allSatisfy({$0.isFinite}),capture.width>0,capture.height>0,viewport.width>24,viewport.height>24,
              region.width>0,region.height>0,toolbar.width>0,toolbar.height>0,
              parameters.width>=0,parameters.height>=0 else {return nil}
        let captureRect=CGRect(origin:.zero,size:capture)
        let visible=region.intersection(captureRect)
        guard allowsOutsideRegion ? (!visible.isNull && !visible.isEmpty) : captureRect.contains(region) else {return nil}
        let scale=min(viewport.width/capture.width,viewport.height/capture.height)
        let background=CGRect(x:(viewport.width-capture.width*scale)/2,y:(viewport.height-capture.height*scale)/2,width:capture.width*scale,height:capture.height*scale)
        let image=CGRect(x:background.minX+region.minX*scale,y:background.minY+region.minY*scale,width:region.width*scale,height:region.height*scale)
        let screenPadding: CGFloat = 12
        let toolbarGap: CGFloat = 14
        let parameterGap: CGFloat = 8
        let safeWidth = viewport.width - 2 * screenPadding
        let safeHeight = viewport.height - 2 * screenPadding
        let toolbarWidth = min(toolbar.width, safeWidth)
        let toolbarHeight = min(toolbar.height, safeHeight)
        let availableHeight = max(0, safeHeight - toolbarHeight - parameterGap)
        let parameterHeight = parameters.width > 0 ? min(parameters.height, availableHeight) : 0
        // 首排靠近选区，样式面板放在首排远离选区的一侧。
        let reservedSpace = parameterGap + min(max(116, parameterHeight), availableHeight)
        let neededSpace = parameterHeight > 0 ? parameterGap + parameterHeight : 0
        let belowY = image.minY - toolbarGap - toolbarHeight
        let aboveY = image.maxY + toolbarGap
        let roomBelow = belowY - screenPadding
        let roomAbove = viewport.height - screenPadding - aboveY - toolbarHeight
        let y: CGFloat
        let parametersAbove: Bool
        if roomBelow >= reservedSpace || (roomAbove < reservedSpace && roomBelow >= neededSpace) {
            y = belowY
            parametersAbove = false
        } else if roomAbove >= neededSpace {
            y = aboveY
            parametersAbove = true
        } else if roomBelow >= roomAbove {
            // 大选区放不下两排时，先把首排保在边缘，参数再向内侧展开。
            y = min(max(screenPadding, belowY), viewport.height - screenPadding - toolbarHeight - neededSpace)
            parametersAbove = true
        } else {
            y = max(screenPadding + neededSpace, min(aboveY, viewport.height - screenPadding - toolbarHeight))
            parametersAbove = false
        }
        let x = max(screenPadding, min(image.midX - toolbarWidth / 2, viewport.width - screenPadding - toolbarWidth))
        let primary = CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
        var panel: CGRect?
        if parameterHeight > 0 {
            let width = min(parameters.width, safeWidth)
            let panelY = parametersAbove ? primary.maxY + parameterGap : primary.minY - parameterGap - parameterHeight
            panel = CGRect(x: max(screenPadding, min(x + 8, viewport.width - screenPadding - width)),
                           y: panelY, width: width, height: parameterHeight)
        }
        return ScreenshotPlacement(background:background,image:image,toolbar:primary,parameters:panel)
    }
}
