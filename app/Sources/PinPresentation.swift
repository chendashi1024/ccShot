import AppKit

enum PinLayout {
    static func frame(pixels:CGSize,scale:CGFloat,visible:CGRect,preferred:CGRect?=nil)->CGRect {
        let size=preferred?.size ?? CGSize(width:pixels.width/max(1,scale),height:pixels.height/max(1,scale))
        let width=size.width,height=size.width*pixels.height/pixels.width
        let fit=min(1,min(visible.width/width,visible.height/height))
        let result=CGSize(width:width*fit,height:height*fit)
        let x=preferred?.minX ?? visible.midX-result.width/2
        let y=preferred.map {$0.maxY-result.height} ?? visible.midY-result.height/2
        return CGRect(x:max(visible.minX,min(x,visible.maxX-result.width)),y:max(visible.minY,min(y,visible.maxY-result.height)),width:result.width,height:result.height)
    }
}

@MainActor final class PinSurface:NSView {
    var onLayout:(()->Void)?
    var onHover:((Bool)->Void)?
    var paintsBackground=false
    private var tracking:NSTrackingArea?
    override func layout() {super.layout();onLayout?()}
    override func draw(_ dirtyRect:NSRect) {if paintsBackground {CoreAppearance.surface.setFill();dirtyRect.fill()}}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsDisplay=true}
    override func updateTrackingAreas() {
        if let tracking {removeTrackingArea(tracking)}
        let value=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        tracking=value;addTrackingArea(value);super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) {onHover?(true)}
    override func mouseExited(with event:NSEvent) {onHover?(false)}
}

@MainActor final class PinPanel:NSPanel {
    var acceptsKey=false
    override var canBecomeKey:Bool {acceptsKey}
    override var canBecomeMain:Bool {false}
}

@MainActor final class PinChrome {
    let primary:PinPanel
    let secondary:PinPanel
    private let primaryContent:NSStackView
    private let secondaryContent:NSStackView
    private weak var parent:NSWindow?
    private var hovering:Set<Int>=[]
    private var pendingHide:DispatchWorkItem?
    private var observers:[NSObjectProtocol]=[]
    private var hasSecondary=false
    private var closed=false
    var isAuxiliaryActive:()->Bool={false}

    init(parent:NSWindow,root:PinSurface,owner:NSResponder,primaryRows:[NSView],secondaryRows:[NSView]) {
        self.parent=parent
        func make(_ rows:[NSView])->(PinPanel,NSStackView,PinSurface) {
            let panel=PinPanel(contentRect:CGRect(x:0,y:0,width:200,height:56),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false;panel.isOpaque=false;panel.backgroundColor = .clear
            panel.level = .floating;panel.hasShadow=true;panel.nextResponder=owner
            let surface=PinSurface();surface.paintsBackground=true;surface.wantsLayer=true;surface.layer?.cornerRadius=10;surface.layer?.masksToBounds=true
            surface.layer?.borderWidth=1;surface.layer?.borderColor=NSColor.separatorColor.cgColor
            let stack=NSStackView(views:rows);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
            surface.addSubview(stack);panel.contentView=surface
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:surface.leadingAnchor,constant:8),stack.trailingAnchor.constraint(equalTo:surface.trailingAnchor,constant:-8),stack.topAnchor.constraint(equalTo:surface.topAnchor,constant:8),stack.bottomAnchor.constraint(equalTo:surface.bottomAnchor,constant:-8)])
            parent.addChildWindow(panel,ordered:.above)
            return(panel,stack,surface)
        }
        let first=make(primaryRows),second=make(secondaryRows)
        primary=first.0;primaryContent=first.1;secondary=second.0;secondaryContent=second.1;secondary.acceptsKey=true
        for (index,surface) in [root,first.2,second.2].enumerated() {
            surface.onHover={ [weak self] inside in
                guard let self else {return}
                if inside {hovering.insert(index)} else {hovering.remove(index)}
                refreshVisibility()
            }
        }
        for name in [NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.refreshVisibility()}
            })
        }
    }
    func layout(editing:Bool) {
        guard let parent,let screen=parent.screen ?? NSScreen.main,!closed else {return}
        let visible=screen.visibleFrame,first=primaryContent.fittingSize,second=secondaryContent.fittingSize
        let firstSize=CGSize(width:first.width+16,height:first.height+16)
        hasSecondary=secondaryContent.arrangedSubviews.contains{!$0.isHidden}
        let secondSize=hasSecondary ? CGSize(width:second.width+16,height:second.height+16) : .zero
        if editing,let placement=ScreenshotLayout.make(capture:visible.size,region:parent.frame.offsetBy(dx:-visible.minX,dy:-visible.minY),viewport:visible.size,toolbar:firstSize,parameters:secondSize,allowsOutsideRegion:true) {
            primary.setFrame(placement.toolbar.offsetBy(dx:visible.minX,dy:visible.minY),display:true)
            if let frame=placement.parameters {secondary.setFrame(frame.offsetBy(dx:visible.minX,dy:visible.minY),display:true)}
        } else {
            let top=parent.frame.maxY+4
            let y=top+firstSize.height<=visible.maxY ? top : parent.frame.maxY-firstSize.height-6
            let x=max(visible.minX+8,min(parent.frame.maxX-firstSize.width,visible.maxX-firstSize.width-8))
            primary.setFrame(CGRect(x:x,y:max(visible.minY+8,y),width:firstSize.width,height:firstSize.height),display:true)
            if hasSecondary {
                let sy=max(visible.minY+8,min(parent.frame.minY-secondSize.height-8,visible.maxY-secondSize.height-8))
                secondary.setFrame(CGRect(x:max(visible.minX+8,min(parent.frame.minX,visible.maxX-secondSize.width-8)),y:sy,width:secondSize.width,height:secondSize.height),display:true)
            }
        }
        refreshVisibility()
    }
    private var shouldShow:Bool {
        guard let parent,parent.isVisible,!closed else {return false}
        return parent.isKeyWindow || primary.isKeyWindow || secondary.isKeyWindow || !hovering.isEmpty || isAuxiliaryActive()
    }
    func refreshVisibility() {
        pendingHide?.cancel();pendingHide=nil
        if shouldShow {
            primary.orderFront(nil)
            if hasSecondary {secondary.orderFront(nil)} else {secondary.orderOut(nil)}
        } else {
            let task=DispatchWorkItem { [weak self] in
                guard let self,!shouldShow else {return}
                primary.orderOut(nil);secondary.orderOut(nil)
            }
            pendingHide=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:task)
        }
    }
    func close() {
        closed=true;pendingHide?.cancel();pendingHide=nil
        for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]
        for panel in [primary,secondary] {parent?.removeChildWindow(panel);panel.nextResponder=nil;panel.close()}
    }
}
