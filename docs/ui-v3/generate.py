#!/usr/bin/env python3
"""生成核心功能版设计候选；复用第二版自制素材，不接入或改动原生 App。"""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ccshot_ui_v2', ROOT.parent / 'ui-v2/generate.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
rect, text, line, circle, icon, action = base.rect, base.text, base.line, base.circle, base.icon, base.action
INK, MUTED, GREEN, PAPER = '#282d2a', '#626c65', '#285c53', '#fafbf8'
base.PATHS['back'] = '<path d="M15 5l-7 7 7 7"/>'
base.PATHS['cover'] = '<rect x="3" y="6" width="18" height="12" rx="2" fill="currentColor" stroke="none"/>'
TOOLS = [('arrow','箭头'),('rectangle','画框'),('text','文字'),('cover','遮挡')]
COLORS = ['#c64635', '#285c53', '#2e63a5', '#252b28']


def panel(x, y, w, h, r=12):
    return rect(x,y,w,h,PAPER,r,'#cbd1c9','filter="url(#shadow)"')


def control(x,y,w,label,symbol=None,attrs='',primary=False,active=False):
    color = '#fff' if primary else GREEN if active else INK
    body = rect(x,y,w,40,GREEN if primary else '#e6eee8' if active else 'transparent',8)
    if symbol:
        body += icon(symbol,x+12,y+10,20,color)
    body += text(x+(42 if symbol else w/2),y+26,label,15,color,500,'' if symbol else 'text-anchor="middle"')
    return action(body,label,attrs)


def backdrop():
    out=rect(0,0,1440,900,'#dce1d9')
    out+='<path d="M0 740Q430 190 960 290T1440 570V900H0Z" fill="#cbd5cd"/><path d="M0 830Q750 360 1440 700V900H0Z" fill="#bdcbbf"/>'
    out+=rect(0,0,1440,32,'#eef2eb')+text(24,22,'●',15,INK)+text(57,22,'备忘录',13,INK,600)+text(128,22,'文件',13)+text(178,22,'编辑',13)+text(228,22,'显示',13)+text(1245,22,'周二  11月3日  11:03',12,INK)
    out+=panel(176,101,1088,582)+base.dots(200,122)
    out+=line(176,143,1264,143,'#dce0d7')+text(720,126,'工作手记',12,MUTED,500,'text-anchor="middle"')
    out+=rect(177,144,166,538,'#eeefe8')+text(205,185,'我的笔记',14,MUTED,500)
    out+=rect(190,204,140,34,'#e0e5d9',6)+text(207,227,'工作手记',13,INK)+text(207,269,'阅读摘录',13,MUTED)+text(207,311,'周末计划',13,MUTED)
    out+=rect(343,144,920,538,'#fffdf9')+base.note(380,188)
    return out


def image_content(annotated=False):
    out=rect(362,170,716,450,'#fffdf9')+base.note(380,188)
    if annotated:
        shapes={
            'arrow':'<path d="M924 523Q861 472 767 480M782 469l-15 11 18 2" fill="none"/>',
            'rectangle':'<rect x="434" y="465" width="335" height="35" rx="4" fill="none"/>',
            'text':'<text x="832" y="489" font-size="22" fill="currentColor" stroke="none">这里补图</text>',
            'cover':'<rect x="438" y="466" width="329" height="32" rx="2" fill="currentColor" stroke="none"/>',
        }
        for name,shape in shapes.items():
            out+=f'<g data-mark="{name}" style="display:{"inline" if name=="arrow" else "none"}" color="{COLORS[0]}" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">{shape}</g>'
    return '<g data-export-content="true">'+out+'</g>'


def crop():
    out='<path d="M0 32H1440V900H0Z M362 170V620H1078V170Z" fill="#24362d" opacity=".22" fill-rule="evenodd"/>'
    out+=rect(362,170,716,450,'none',0,'#ffffff','stroke-width="1.5"')
    for xx,yy in [(362,170),(720,170),(1078,170),(362,395),(1078,395),(362,620),(720,620),(1078,620)]:
        out+=rect(xx-3,yy-3,6,6,'#fff',1,GREEN)
    out+=rect(362,139,112,22,'#28372fe6',5)+text(371,154,'1432 × 900 px',11,'#fff',500)
    return '<g data-ui="true">'+out+'</g>'


def mainbar(selected_text=False):
    x,y=475,648
    out=panel(x,y,490,56)
    out+=control(x+8,y+8,94,'标注','pencil','data-scene="annotate"')
    out+=control(x+102,y+8,94,'钉住','pin','data-scene="pin"')
    out+=control(x+196,y+8,94,'保存','save','data-action="save"')
    out+=line(x+294,y+15,x+294,y+41,'#d5dcd3')
    out+=control(x+304,y+8,128,'复制文字' if selected_text else '复制','copy',f'data-action="{"copy-text" if selected_text else "copy"}"',True)
    out+=action(rect(x+438,y+8,44,40,'transparent',8)+icon('close',x+450,y+18,20,INK),'结束截图','data-action="close"')
    return out


def capture():
    return backdrop()+image_content()+crop()+mainbar()


def selection():
    out=backdrop()+image_content()+crop()
    out+=rect(414,294,158,25,'#c4dbd0',2)+text(416,315,'把重要的决定留下来',17,'#243d32')+line(572,292,572,320,GREEN,1.4)
    return out+mainbar(True)


def style_popover():
    x,y=807,716
    out=panel(x,y,232,148,10)+text(x+16,y+28,'颜色',13,MUTED)
    for i,color in enumerate(COLORS):
        xx=x+29+i*51
        out+=action(rect(xx-20,y+36,40,34,'transparent',6)+circle(xx,y+53,10,color)+circle(xx,y+53,14,'none',GREEN if i==0 else 'none',f'data-ring="{color}"'),f'标注颜色 {color}',f'data-color="{color}"')
    out+=line(x+16,y+80,x+216,y+80,'#e0e5dd')+text(x+16,y+104,'粗细',13,MUTED,extra='data-param-label="true"')
    for i,(width,label) in enumerate([(2,'细'),(4,'中'),(6,'粗')]):
        xx=x+68+i*50
        out+=action(rect(xx,y+87,42,43,'#e6eee8' if width==4 else 'transparent',7,extra=f'data-width-bg="{width}"')+text(xx+21,y+114,label,14,INK,500,'text-anchor="middle" data-width-text="true"'),label,f'data-width="{width}"')
    return '<g data-popover="true" style="display:none">'+out+'</g>'


def annotate():
    x,y=395,648
    out=backdrop()+image_content(True)+crop()+panel(x,y,650,56)
    out+=action(rect(x+8,y+8,42,40,'transparent',8)+icon('back',x+19,y+18,20,INK),'返回截图','data-scene="capture"')
    out+=line(x+56,y+15,x+56,y+41,'#d5dcd3')
    for i,(name,label) in enumerate(TOOLS):
        out+=control(x+65+i*87,y+8,85,label,name,f'data-tool="{name}" aria-pressed="{str(i==0).lower()}"',active=i==0)
    out+=line(x+420,y+15,x+420,y+41,'#d5dcd3')
    body=rect(x+429,y+8,96,40,'transparent',8)+circle(x+448,y+28,7,COLORS[0],extra='data-style-dot="true"')+text(x+464,y+34,'样式',14,INK)+icon('chevron',x+500,y+21,15,INK)
    out+=action(body,'调整标注样式','data-action="style" aria-expanded="false"')
    out+=control(x+536,y+8,106,'完成','check','data-scene="capture"',True)
    return out+style_popover()


def pinned():
    out=backdrop()+rect(0,32,1440,868,'#f0f3ee80')
    out+=panel(362,170,716,450,0)+image_content(True)
    out+=panel(790,126,288,40,9)
    out+=control(794,126,94,'标注','pencil','data-scene="annotate"')
    out+=control(890,126,94,'复制','copy','data-action="copy"')
    out+=action(rect(991,126,80,40,'transparent',7)+icon('close',1002,136,20,INK)+text(1029,152,'关闭',14,INK),'关闭钉图','data-action="close"')
    return out


def settings():
    out=backdrop()+rect(0,32,1440,868,'#e9eee7bd')
    x,y=420,282
    out+=panel(x,y,600,314,16)+base.dots(x+24,y+24)
    out+=text(x+32,y+80,'设置',26,INK,600)
    out+=text(x+32,y+138,'截图快捷键',16,INK)
    out+=action(rect(x+392,y+110,174,40,'#fff',8,'#d4dbd0')+text(x+479,y+136,'F1',15,INK,500,'text-anchor="middle"'),'录入截图快捷键；部分键盘需要 Fn + F1','data-action="hotkey" data-setting="hotkey"')
    out+=line(x+32,y+165,x+568,y+165,'#dce1d8')
    out+=text(x+32,y+209,'保存位置',16,INK)
    out+=action(rect(x+392,y+181,174,40,'#fff',8,'#d4dbd0')+icon('folder',x+407,y+191,20,MUTED)+text(x+440,y+207,'桌面',15,INK,extra='data-folder-label="true"')+icon('chevron',x+536,y+194,15,MUTED),'更改保存位置','data-action="folder"')
    return out


SCENES=[('capture','截图',capture),('annotate','标注',annotate),('selection','选字',selection),('pin','钉图',pinned),('settings','设置',settings)]

SCRIPT=r'''
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
let current='capture', tool='arrow', color='#c64635', width=4, hasMark=false;
const hints={capture:'示例截图：标注、钉住与输出都从这里开始。保存与复制使用示例图片。',annotate:'点击工具查看示例标记，点击「样式」调整颜色和粗细。这里尚不支持自由绘制。',selection:'固定选字示例；复制会尝试写入这段示例文字，尚未接入 OCR。',pin:'钉图操作栏的显现状态。网页未连接系统置顶窗口。',settings:'只演示两项设置；切换值不会更改 macOS。'};
const announce = message => { $('#status').textContent=message; };
function syncMarks() {
  $$('.scene [data-export-content]').forEach(group=>{
    if (!group.querySelector('[data-mark]')) {
      const source=$('[data-scene-id="annotate"] [data-export-content]');
      source.querySelectorAll('[data-mark]').forEach(mark=>group.append(mark.cloneNode(true)));
    }
    group.querySelectorAll('[data-mark]').forEach(mark=>{
      const ownScene=group.closest('.scene').dataset.sceneId;
      mark.style.display=mark.dataset.mark===tool && (hasMark || ownScene==='annotate')?'inline':'none';
      mark.setAttribute('color',color); mark.setAttribute('stroke-width',width);
      const text=mark.querySelector('text'); if(text) text.setAttribute('font-size',{2:18,4:22,6:28}[width]);
    });
  });
}
function show(scene) {
  if (current==='annotate' && scene!=='annotate') hasMark=true;
  current=scene; $$('.scene').forEach(el=>el.hidden=el.dataset.sceneId!==scene);
  $$('nav [data-scene]').forEach(el=>el.setAttribute('aria-pressed',el.dataset.scene===scene));
  $('[data-popover]').style.display='none'; $('[data-action="style"]').setAttribute('aria-expanded','false');
  syncMarks(); announce(hints[scene]);
}
function chooseTool(name) {
  tool=name;
  $$('[data-tool]').forEach(el=>{
    const active=el.dataset.tool===tool; el.setAttribute('aria-pressed',active);
    el.querySelector('rect').setAttribute('fill',active?'#e6eee8':'transparent');
  });
  const covered=tool==='cover';
  $('[data-param-label]').textContent=tool==='text'?'字号':'粗细';
  $$('[data-width]').forEach((el,i)=>{
    el.style.display=covered?'none':'inline';
    el.querySelector('[data-width-text]').textContent=tool==='text'?['18','22','28'][i]:['细','中','粗'][i];
  });
  $('[data-param-label]').style.display=covered?'none':'inline';
  syncMarks();
}
async function imageBlob() {
  const scene=$(`[data-scene-id="${current}"] svg`);
  const output=document.createElementNS('http://www.w3.org/2000/svg','svg');
  output.setAttribute('xmlns','http://www.w3.org/2000/svg'); output.setAttribute('width','1432'); output.setAttribute('height','900');
  output.setAttribute('viewBox','362 170 716 450'); output.setAttribute('style',scene.getAttribute('style'));
  output.append(scene.querySelector('defs').cloneNode(true),scene.querySelector('[data-export-content]').cloneNode(true));
  const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(output)],{type:'image/svg+xml'}));
  try {
    const image=new Image(); image.src=url; await image.decode();
    const canvas=document.createElement('canvas'); canvas.width=1432; canvas.height=900;
    canvas.getContext('2d').drawImage(image,0,0);
    return await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('无法编码图片')),'image/png'));
  } finally { URL.revokeObjectURL(url); }
}
async function activate(el) {
  if(el.dataset.scene) return show(el.dataset.scene);
  if(el.dataset.tool) return chooseTool(el.dataset.tool);
  if(el.dataset.color) {
    color=el.dataset.color; $$('[data-ring]').forEach(r=>r.setAttribute('stroke',r.dataset.ring===color?'#285c53':'none'));
    $('[data-style-dot]').setAttribute('fill',color); return syncMarks();
  }
  if(el.dataset.width) {width=Number(el.dataset.width); $$('[data-width-bg]').forEach(r=>r.setAttribute('fill',Number(r.dataset.widthBg)===width?'#e6eee8':'transparent'));return syncMarks();}
  const name=el.dataset.action;
  if(name==='style') {const open=el.getAttribute('aria-expanded')!=='true';el.setAttribute('aria-expanded',open);$('[data-popover]').style.display=open?'inline':'none';return;}
  if(name==='close') {show('capture');announce('演示已回到截图画面；网页不会关闭真实窗口。');return;}
  if(name==='hotkey') {const value=el.querySelector('text');value.textContent=value.textContent==='F1'?'⌃⌥S':'F1';announce('快捷键外观演示；原生版通过按键录入并检查冲突。');return;}
  if(name==='folder') {const value=$('[data-folder-label]');value.textContent=value.textContent==='桌面'?'下载':'桌面';announce('目录外观演示；原生版使用系统文件夹选择器。');return;}
  try {
    if(name==='copy-text') {await navigator.clipboard.writeText('把重要的决定留下来');announce('示例文字已复制。');}
    if(name==='copy') {
      if(!navigator.clipboard?.write || !window.ClipboardItem) throw new Error('当前浏览器不支持复制图片，请保存示例图片。');
      await navigator.clipboard.write([new ClipboardItem({'image/png':imageBlob()})]);announce('示例图片已复制。');
    }
    if(name==='save') {
      const url=URL.createObjectURL(await imageBlob());const link=document.createElement('a');link.href=url;link.download='CcShot-示例截图.png';link.click();
      setTimeout(()=>URL.revokeObjectURL(url),10000);announce('已发起示例 PNG 下载；请在浏览器下载记录中查看。');
    }
  } catch(error) {announce('操作未完成：'+(error.message || '浏览器未允许此操作。'));}
}
document.addEventListener('click',event=>{const el=event.target.closest('[data-scene],[data-tool],[data-color],[data-width],[data-action]');if(el) activate(el);});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape') {
    const panel=$('[data-popover]'); if(panel.style.display!=='none'){panel.style.display='none';$('[data-action="style"]').setAttribute('aria-expanded','false');$('[data-action="style"]').focus();}
    else if(current==='annotate')show('capture');return;
  }
  if((event.key==='Enter'||event.key===' ') && event.target.matches('g[role="button"]')){event.preventDefault();activate(event.target);}
});
show('capture');
'''


def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    nav, boards=[],[]
    for i,(name,label,render) in enumerate(SCENES):
        drawing=base.svg(name,label,render())
        (ROOT/f'{name}.svg').write_text(drawing,encoding='utf-8')
        nav.append(f'<button data-scene="{name}" aria-pressed="{str(i==0).lower()}">{label}</button>')
        boards.append(f'<section class="scene" data-scene-id="{name}" {"hidden" if i else ""}>{drawing.replace(chr(34)+"img"+chr(34),chr(34)+"group"+chr(34),1)}</section>')
    html='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>CcShot · 核心功能版试稿</title><style>
*{box-sizing:border-box}body{margin:0;background:#edf0e9;color:#282d2a;font:14px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;min-width:1000px}header{height:76px;padding:0 34px;display:flex;align-items:center;gap:24px;background:#fafbf8;border-bottom:1px solid #d5dcd1}.brand{font-size:22px;font-weight:650;letter-spacing:-.7px}.draft{font-size:13px;color:#626c65}nav{display:flex;gap:4px;margin:auto}nav button{background:none;border:0;border-radius:8px;padding:9px 20px;font:inherit;color:#626c65;cursor:pointer}nav button[aria-pressed=true]{background:#e2eadf;color:#285c53;font-weight:600}a{color:#506a57;text-decoration:none}main{max-width:1500px;margin:24px auto;padding:0 30px}.scene{border-radius:12px;overflow:hidden;border:1px solid #c6d0c2;box-shadow:0 18px 60px #334d3620}.scene[hidden]{display:none}.scene>svg{display:block;width:100%;height:auto}.scene g[role=button]{cursor:pointer}.scene g[role=button]:hover>rect:first-of-type{filter:brightness(.97)}.scene g[role=button]:focus-visible{outline:2px solid #285c53;outline-offset:3px}button:focus-visible,a:focus-visible{outline:2px solid #285c53;outline-offset:3px}footer{display:flex;align-items:center;justify-content:space-between;gap:24px;min-height:54px;color:#626c65;font-size:13px}
</style></head><body><header><span class="brand">CcShot</span><span class="draft">核心功能版 · 设计演示</span><nav aria-label="设计画面">'''+''.join(nav)+'''</nav><a href="../UI参考与设计.md">设计说明 ↗</a></header><main>'''+''.join(boards)+'''<footer><span id="status" role="status" aria-live="polite"></span><a href="../ui-v2/设计稿.html">上一版 ↗</a></footer></main><script>'''+SCRIPT+'</script></body></html>'
    (ROOT/'设计稿.html').write_text(html,encoding='utf-8')
    print('已生成五个 SVG 画板和离线设计演示。')
    import sys
    if '--png' in sys.argv:
        from contextlib import redirect_stdout
        from io import StringIO
        base.ROOT=ROOT
        base.SCENES=SCENES
        with redirect_stdout(StringIO()):
            base.export_png()
        print('已导出五张 1440×900 PNG 设计画板。')


if __name__=='__main__':
    main()
