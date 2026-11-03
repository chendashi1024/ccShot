# S0 范围与按键排障

2026-11-03，macOS 15.4.1、arm64；只使用原型自带虚构文字样本，无付费请求、无新增权限。S0 未通过，完整产品未实现。

- 基线 `baseline-selection.jsonl`：请求前四字“今天下午”，原生 `selectedText` 返回五字“今天下午三”，可复现。
- `range-diagnostic.jsonl`：中间位置及单字同样多包含下一字；末字被全文边界裁住。说明差异已在原生选择范围读取时发生，不是剪贴板附加字符。
- `adjusted-probe.jsonl`：上界减一个字符可暂时使多字相等，但单字变为空，因此没有采用这个办法修产品，也未篡改失败预期。
- `targeted-key-events.jsonl`：CUA 对应用发送的 Control+Option+S、F1 与 Command+A 能到达本地事件处理，未见全局热键回调。它不等于实体键盘或全局输入路径的测试，不能认定 Carbon 代码故障或全局快捷键通过。仅保留三个目标修饰键事件，普通输入不归档。
- `final-selftest.jsonl`：最终源码构建后的原生选区自检依然失败；新的 `--exit-after-self-test` 返回退出码 1，避免脚本误把进程正常结束当作选字通过。

复现：先 `bash build.sh`，随后使用 README 的固定样本命令，另加 `--self-test --exit-after-self-test`。`--diagnose-keys` 仅在提供 `--fixture` 时启用，只记录三个指定测试快捷键的键码/修饰键，不记录普通输入。`verification.json` 绑定最终源码哈希。历史 2026-11-03-native-01 证据保留。

下一步：本地体验继续优先使用已验证的真实鼠标选字路线，不让产品依赖任意子串的程序化范围设置；若后续功能需要它，须解决单字及 Unicode 范围并重新验证。全局快捷键保留菜单入口，实体键盘路径单列待测；不能因此把全部产品开发停在旧文档确认上。
