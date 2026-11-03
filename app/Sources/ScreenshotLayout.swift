import AppKit

struct ScreenshotPlacement {
    let background: CGRect
    let image: CGRect
    let toolbar: CGRect
    let parameters: CGRect?
}

enum ScreenshotLayout {
    static func make(capture: CGSize, region: CGRect, viewport: CGSize, toolbar: CGSize, parameters: CGSize, toolbarAnchorWidth:CGFloat?=nil) -> ScreenshotPlacement? {
        let values=[capture.width,capture.height,region.minX,region.minY,region.width,region.height,viewport.width,viewport.height,toolbar.width,toolbar.height,parameters.width,parameters.height]
        guard values.allSatisfy({$0.isFinite}),capture.width>0,capture.height>0,viewport.width>24,viewport.height>24,
              region.width>0,region.height>0,CGRect(origin:.zero,size:capture).contains(region),toolbar.width>0,toolbar.height>0,
              parameters.width>=0,parameters.height>=0 else {return nil}
        let scale=min(viewport.width/capture.width,viewport.height/capture.height)
        let background=CGRect(x:(viewport.width-capture.width*scale)/2,y:(viewport.height-capture.height*scale)/2,width:capture.width*scale,height:capture.height*scale)
        let image=CGRect(x:background.minX+region.minX*scale,y:background.minY+region.minY*scale,width:region.width*scale,height:region.height*scale)
        let safeWidth=viewport.width-24,safeHeight=viewport.height-24
        let tw=min(toolbar.width,safeWidth),th=min(toolbar.height,safeHeight)
        let hasParameters=parameters.width>0 && parameters.height>0
        let ph=hasParameters ? min(parameters.height,max(0,safeHeight-th-12)) : 0
        // 为通常的两行参数预留位置，切换工具时首排不因面板出现而跳动。
        let reserve=min(max(116,ph),max(0,safeHeight-th-12))
        let groupHeight=th+12+reserve
        let y:CGFloat
        if image.minY-28-groupHeight>=12 {y=image.minY-28-th}
        else if image.maxY+28+groupHeight<=viewport.height-12 {y=image.maxY+28+reserve+12}
        else {y=max(12,min(image.minY+12,viewport.height-12-groupHeight))+reserve+12}
        let anchor=min(toolbarAnchorWidth ?? tw,safeWidth)
        let reservedWidth=min(safeWidth,max(tw,anchor+28))
        let x=max(12,min(image.midX-anchor/2,viewport.width-12-reservedWidth))
        let primary=CGRect(x:x,y:y,width:tw,height:th)
        var panel:CGRect?
        if hasParameters {
            let pw=min(parameters.width,safeWidth)
            panel=CGRect(x:max(12,min(x+8,viewport.width-12-pw)),y:y-12-ph,width:pw,height:ph)
        }
        return ScreenshotPlacement(background:background,image:image,toolbar:primary,parameters:panel)
    }
}
