import AppKit

extension AppPreferences {
    func annotationStyle(for tool: AnnotationTool) -> AnnotationStyle {
        let key = "ccshot.annotation.style.\(tool.rawValue).v1"
        guard let data = store.data(forKey: key), let style = try? JSONDecoder().decode(AnnotationStyle.self, from: data), style.valid else { return .initial(tool) }
        return style
    }
    func setAnnotationStyle(_ style: AnnotationStyle, for tool: AnnotationTool) {
        guard style.valid, tool != .select else { return }
        store.set(try? JSONEncoder().encode(style), forKey: "ccshot.annotation.style.\(tool.rawValue).v1")
    }
}
