import AppKit

// 供真人或CUA在本应用虚构样本中点击复制。只报告精确匹配，不记录原剪贴板。
@main struct ClipboardCopyProbe {
    static func main() {
        let args=CommandLine.arguments
        guard args.count==3 else {exit(2)}
        let pasteboard=NSPasteboard.general
        let saved=pasteboard.pasteboardItems?.map{item -> NSPasteboardItem in
            let copy=NSPasteboardItem()
            for type in item.types {if let data=item.data(forType:type){copy.setData(data,forType:type)}}
            return copy
        } ?? []
        let initial=pasteboard.changeCount,deadline=ProcessInfo.processInfo.systemUptime+20
        FileHandle.standardOutput.write(Data("等待点击复制\n".utf8))
        while pasteboard.changeCount==initial && ProcessInfo.processInfo.systemUptime<deadline {Thread.sleep(forTimeInterval:0.05)}
        let observed=pasteboard.changeCount
        let copied=pasteboard.string(forType:.string) ?? ""
        let matched=observed != initial && copied==args[1]
        let corpus="今天下午三点半，我们在图书馆门口见面。\n请带上笔记本电脑，提前检查电量和网络。\n截图里的文字应该可以直接选择、复制。"
        let fromFixture = observed != initial && !copied.isEmpty && corpus.contains(copied)
        var restored=false
        if fromFixture && pasteboard.changeCount==observed {pasteboard.clearContents();restored=saved.isEmpty || pasteboard.writeObjects(saved)}
        let result: [String:Any]=["exact_match":matched,"previous_clipboard_restored":restored,"original_clipboard_logged":false,"passed":matched && restored]
        let data=try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        try! data.write(to:URL(fileURLWithPath:args[2]),options:.atomic)
        exit(matched && restored ? 0:1)
    }
}
