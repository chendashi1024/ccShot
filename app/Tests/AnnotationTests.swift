import AppKit

@main struct AnnotationTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let base = context.makeImage()!
        let defaultArrow = AnnotationObject(tool: .arrow, style: .initial(.arrow), start: CGPoint(x: 20, y: 50), end: CGPoint(x: 180, y: 50))
        let arrowImage = AnnotationRenderer.render(base: base, objects: [defaultArrow])!
        precondition(PixelSampler.color(in: arrowImage, x: 90, y: 47)!.green < 100, "默认箭杆至少覆盖 6 个像素")
        precondition(defaultArrow.style.arrowHead == .open, "默认箭头应使用开口夹角")
        precondition(PixelSampler.color(in: arrowImage, x: 166, y: 45)!.hex == "#FFFFFF"
                     && PixelSampler.color(in: arrowImage, x: 166, y: 40)!.green < 100, "箭头两翼清晰可见，夹角中间保持空白")
        var filledArrow = defaultArrow
        filledArrow.style.arrowHead = .filled
        let filledArrowImage = AnnotationRenderer.render(base: base, objects: [filledArrow])!
        precondition(PixelSampler.color(in: filledArrowImage, x: 182, y: 49)!.hex == "#FFFFFF", "箭杆的圆端不能伸到箭尖前方")
        let retina = AnnotationStyle.defaultScale(imageSize: CGSize(width: 2400, height: 1600), displayedWidth: 1200)
        let fitted = AnnotationStyle.defaultScale(imageSize: CGSize(width: 3840, height: 2160), displayedWidth: 960)
        let small = AnnotationStyle.defaultScale(imageSize: CGSize(width: 180, height: 80), displayedWidth: 90)
        precondition(retina == 2 && fitted == 4 && small < 1, "默认样式兼顾 Retina、大图缩放和小选区")
        precondition(AnnotationStyle.initial(.arrow, scale: retina).width == 12 && AnnotationStyle.initial(.arrow, scale: fitted).width == 24)
        precondition(AnnotationStyle.initial(.text, scale: retina).fontSize == 40 && AnnotationStyle.initial(.highlight, scale: retina).width == 40)
        precondition(AnnotationTool.allCases.allSatisfy { AnnotationStyle.initial($0, scale: fitted).valid })
        var shortArrow = defaultArrow
        shortArrow.end = CGPoint(x: 32, y: 50)
        shortArrow.style = .initial(.arrow, scale: retina)
        let shortImage = AnnotationRenderer.render(base: base, objects: [shortArrow])!
        precondition(shortArrow.arrowHeadLength < 12 && PixelSampler.color(in: shortImage, x: 10, y: 49)!.hex == "#FFFFFF", "短箭头不能在起点后画出尖端")
        let doc = AnnotationDocument(image: base)
        let empty = doc.state
        for index in 0..<120 {
            var state = doc.state
            let shape = AnnotationObject(tool: .rectangle, style: .initial(.rectangle), start: CGPoint(x: index % 100, y: 10), end: CGPoint(x: 150, y: 80))
            state.objects.append(shape); state.nextNumber = index + 2
            doc.commit(state)
        }
        let completed = doc.state
        for _ in 0..<120 { doc.undo() }
        precondition(doc.state == empty && !doc.canUndo && doc.canRedo, "120 次操作应全部撤销")
        for _ in 0..<120 { doc.redo() }
        precondition(doc.state == completed && !doc.canRedo, "120 次重做应精确恢复")
        doc.beginTransaction()
        for width in 1...50 { var state = doc.state; state.objects[0].style.width = CGFloat(width); doc.commit(state) }
        doc.endTransaction(); let styled = doc.state
        doc.undo(); precondition(doc.state == completed, "连续样式拖动只需一次撤销")
        doc.redo(); precondition(doc.state == styled)
        let copy = doc.copied()
        var changed = copy.state; changed.objects.removeAll(); copy.commit(changed)
        precondition(doc.state == styled && copy.state.objects.isEmpty, "钉图副本必须保留对象且独立编辑")
        doc.undo(); var branch = doc.state; branch.nextNumber = 77; doc.commit(branch)
        precondition(!doc.canRedo, "撤销后新操作截断重做分支")
        let mixed = AnnotationDocument(image: base)
        var mixedStates = [mixed.state]
        for index in 0..<120 {
            var state = mixed.state
            switch index % 4 {
            case 0: state.objects.append(AnnotationObject(tool: .ellipse, style: .initial(.ellipse), start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 60)))
            case 1: state.objects[0] = state.objects[0].moved(by: CGPoint(x: 5, y: 8))
            case 2: state.objects[0].style.width = 17
            default: state.objects.removeAll()
            }
            mixed.commit(state); mixedStates.append(state)
        }
        for expected in mixedStates.dropLast().reversed() { mixed.undo(); precondition(mixed.state == expected, "混合历史每一步都须精确恢复") }
        for expected in mixedStates.dropFirst() { mixed.redo(); precondition(mixed.state == expected) }
        let start = AnnotationObject(tool: .rectangle, style: .initial(.rectangle), start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 60))
        let moved = start.moved(by: CGPoint(x: 20, y: 5))
        precondition(moved.bounds == CGRect(x: 30, y: 15, width: 50, height: 50))
        precondition(moved.resized(to: CGRect(x: 20, y: 20, width: 100, height: 50)).bounds == CGRect(x: 20, y: 20, width: 100, height: 50))
        precondition(start.hit(CGPoint(x: 10, y: 30), tolerance: 1) && !start.hit(CGPoint(x: 35, y: 35), tolerance: 1), "空心框内部不应抢走选字")
        var filled = start; filled.style.filled = true
        let rendered = AnnotationRenderer.render(base: base, objects: [filled])!
        let topY = base.height - 1 - 30
        precondition(PixelSampler.color(in: rendered, x: 30, y: topY)!.red > 230 && PixelSampler.color(in: rendered, x: 30, y: topY)!.green < 100, "统一合成必须包含标注像素")
        precondition(PixelSampler.color(in: base, x: 30, y: topY)!.hex == "#FFFFFF", "不可破坏原图")
        for tool in AnnotationTool.allCases where tool != .select {
            let object = AnnotationObject(tool: tool, style: .initial(tool), start: CGPoint(x: 20, y: 20), end: CGPoint(x: 150, y: 70), points: tool == .pen || tool == .highlight ? [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 65), CGPoint(x: 150, y: 30)] : [], number: 123)
            precondition(AnnotationRenderer.render(base: base, objects: [object])?.width == base.width)
        }
        var curve = AnnotationObject(tool:.arrow,style:.initial(.arrow),start:CGPoint(x:20,y:20),end:CGPoint(x:180,y:20))
        curve.curveControl = CGPoint(x:100,y:140)
        precondition(curve.arrowMidpoint == CGPoint(x:100,y:80) && curve.bounds == CGRect(x:20,y:20,width:160,height:60), "曲线中点与实际边界应正确")
        precondition(curve.hit(CGPoint(x:100,y:80),tolerance:1) && !curve.hit(CGPoint(x:100,y:20),tolerance:1), "弯曲后不应选中旧直线")
        let curveImage = AnnotationRenderer.render(base:base,objects:[curve])!
        precondition(PixelSampler.color(in:curveImage,x:100,y:19)!.green < 100 && PixelSampler.color(in:curveImage,x:100,y:79)!.hex == "#FFFFFF", "导出必须渲染弧线且去掉旧直线")
        precondition(curve.resized(to:CGRect(x:10,y:10,width:80,height:30)).arrowMidpoint == CGPoint(x:50,y:40), "缩放应同步曲率")
        for head in ArrowHead.allCases {
            curve.style.arrowHead = head; curve.style.dashed = true
            precondition(AnnotationRenderer.render(base:base,objects:[curve]) != nil, "三种箭头与虚线应兼容弯曲")
        }
        var invalid = filled; invalid.style.width = 0
        precondition(AnnotationRenderer.render(base:base,objects:[invalid]) == nil, "合成失败不得返回原图")
        for effect in [MaskEffect.pixelate,.blur] {
            for brush in [false,true] {
                var style = AnnotationStyle.initial(.mask); style.maskEffect = effect; style.maskBrush = brush; style.width = 20; style.maskStrength = 20
                let mask = AnnotationObject(tool:.mask,style:style,start:CGPoint(x:45,y:20),end:CGPoint(x:80,y:80),points:brush ? [CGPoint(x:60,y:20),CGPoint(x:60,y:80)] : [])
                let output = AnnotationRenderer.render(base:rendered,objects:[mask])!
                let inside = PixelSampler.color(in:output,x:58,y:base.height-1-40)!
                let before = PixelSampler.color(in:rendered,x:58,y:base.height-1-40)!
                precondition(inside.green > before.green, "马赛克/模糊必须实际改变目标像素")
                precondition(PixelSampler.color(in:output,x:30,y:base.height-1-30)!.hex == PixelSampler.color(in:rendered,x:30,y:base.height-1-30)!.hex, "效果不得污染区域外像素")
            }
        }
        let suite = "com.ccshot.annotation-tests.\(UUID().uuidString)"; let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(store: store); var lineStyle = AnnotationStyle.initial(.line); lineStyle.width = 12
        prefs.setAnnotationStyle(lineStyle, for: .line)
        precondition(AppPreferences(store: store).annotationStyle(for: .line, scale: fitted).width == 12 && prefs.annotationStyle(for: .rectangle, scale: retina).width == 8, "旧偏好保持原值，未调整的工具使用新的默认值")
        store.set(Data("bad".utf8), forKey: "ccshot.annotation.style.line.v1")
        precondition(prefs.annotationStyle(for: .line, scale: retina) == .initial(.line, scale: retina), "损坏样式应合法回退")
        print("通过：120步撤销重做、样式事务、对象变换、统一像素、独立钉图与样式记忆")
    }
}
