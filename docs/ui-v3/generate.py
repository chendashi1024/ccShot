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
TOOLS = [('arrow','箭头'),('rectangle','画框'),('text','文字'),('pencil','画笔'),('cover','遮挡'),('highlight','高亮'),('number','序号')]
COLORS = ['#c64635', '#285c53', '#2e63a5', '#252b28']


def panel(x, y, w, h, r=12):
    return rect(x,y,w,h,PAPER,r,'#cbd1c9','filter="url(#shadow)"')


def control(x,y,w,label,symbol=None,attrs='',primary=False,active=False):
    color = '#fff' if primary else GREEN if active else INK
    body = rect(x,y,w,40,GREEN if primary else '#e6eee8' if active else 'transparent',8)
    if symbol:
        label_width=sum(15 if ord(char)>127 else 8 for char in label)
        start=x+(w-20-8-label_width)/2
        body += icon(symbol,start,y+10,20,color)
        body += text(start+28,y+26,label,15,color,500)
    else:
        body += text(x+w/2,y+26,label,15,color,500,'text-anchor="middle"')
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
            'arrow':'<path data-arrow-shaft="true" d="M924 523Q861 472 767 480" fill="none"/><path data-arrow-head="filled" d="M767 480L784 469L786 485Z" fill="currentColor" stroke="none"/><path data-arrow-head="open" d="M782 469L767 480L785 483" fill="none" style="display:none"/><path data-arrow-head="double" d="M767 480L784 469L786 485ZM924 523L907 520L916 508Z" fill="currentColor" stroke="none" style="display:none"/>',
            'rectangle':'<rect x="434" y="465" width="335" height="35" rx="4" fill="none"/>',
            'text':'<rect data-text-background="true" x="826" y="463" width="116" height="34" rx="4" fill="#fff5d7" stroke="none" style="display:none"/><text x="832" y="489" font-size="22" fill="currentColor" stroke="none">这里补图</text>',
            'pencil':'<path d="M440 502Q478 492 512 502T584 502T656 502T730 502" fill="none"/>',
            'cover':'<rect x="438" y="466" width="329" height="32" rx="2" fill="currentColor" stroke="none"/>',
            'highlight':'<path d="M442 476H732" opacity=".35"/>',
            'number':'<circle cx="416" cy="477" r="16" fill="currentColor" stroke="none"/><text x="416" y="483" text-anchor="middle" font-size="16" fill="#fff" stroke="none">1</text>',
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


def mainbar(selected_text=False, selected='pointer'):
    width=986 if selected_text else 956
    # 复制文字会变宽，但已有工具的位置不跟着跳动。
    x,y=242,648
    out=panel(x,y,width,56)
    cursor=x+8
    for name,label in TOOLS:
        out+=control(cursor,y+8,74,label,name,f'data-tool="{name}" aria-pressed="{str(name==selected).lower()}"',active=name==selected)
        cursor+=74
    cursor+=8
    out+=line(cursor,y+15,cursor,y+41,'#d5dcd3');cursor+=9
    for name,label,attrs in [('pointer','选择与选字（V）','data-tool="pointer"'),('undo','撤销示例标记','data-action="undo"'),('redo','重做示例标记','data-action="redo"')]:
        if name=='redo' or (name=='undo' and selected=='pointer'):
            attrs+=' aria-disabled="true" opacity=".35"'
        out+=action(rect(cursor,y+8,36,40,'#e6eee8' if name==selected else 'transparent',7)+icon(name,cursor+8,y+18,20,INK),label,attrs)
        cursor+=42
    cursor+=3
    out+=line(cursor,y+15,cursor,y+41,'#d5dcd3');cursor+=12
    out+=control(cursor,y+8,74,'钉住','pin','data-scene="pin"');cursor+=74
    out+=control(cursor,y+8,74,'保存','save','data-action="save"');cursor+=74
    copy_width=110 if selected_text else 80
    out+=control(cursor,y+8,copy_width,'复制文字' if selected_text else '复制','copy',f'data-action="{"copy-text" if selected_text else "copy"}"',True);cursor+=copy_width
    out+=action(rect(cursor,y+8,36,40,'transparent',8)+icon('close',cursor+8,y+18,20,INK),'结束截图','data-action="close"')
    return out+style_popover(selected,x+8)


def capture():
    return backdrop()+image_content()+crop()+mainbar()


def selection():
    out=backdrop()+image_content()+crop()
    out+=rect(414,294,158,25,'#c4dbd0',2)+text(416,315,'把重要的决定留下来',17,'#243d32')+line(572,292,572,320,GREEN,1.4)
    return out+mainbar(True)


def visual_option(kind, width=2):
    stroke=f'<path d="M6 12H38" stroke="currentColor" stroke-width="{width if kind=="width" else 2}" stroke-linecap="round"'+(' stroke-dasharray="4 3"' if kind=='dashed' else '')+'/>'
    if kind.startswith('fill-'):
        fill='none' if kind=='fill-none' else 'currentColor'
        return f'<rect x="13" y="4" width="18" height="16" rx="1" fill="{fill}" fill-opacity="{0.25 if kind=="fill-soft" else 1}" stroke="currentColor" stroke-width="2"/>'
    if kind=='open':
        return stroke+'<path d="M30 6L39 12L30 18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    if kind in ['filled','double']:
        stroke+='<path d="M39 12L30 6V18Z" fill="currentColor"/>'
        if kind=='double':stroke+='<path d="M5 12L14 6V18Z" fill="currentColor"/>'
    return stroke


def option(x,y,w,label,attrs,active=False,preview=None):
    color=GREEN if active else INK
    body=rect(x,y,w,32,'#e6eee8' if active else '#fff',6,'#d9dfd6')+text(x+w/2,y+22,label,14,color,500,'text-anchor="middle"'+(' style="display:none"' if preview else ''))
    if preview:
        body+=f'<g data-option-preview="true" transform="translate({x+(w-44)/2},{y+4})" color="{color}">{preview}</g>'
    return action(body,label,attrs+f' aria-pressed="{str(active).lower()}"')


def style_popover(selected='pointer', anchor=250):
    out=panel(0,0,512,116,10)
    out+=text(16,34,'颜色',14,MUTED)
    for i,color in enumerate(COLORS):
        xx=72+i*34
        out+=action(rect(xx-16,12,32,36,'transparent',6)+circle(xx,30,9,color)+circle(xx,30,13,'none',GREEN if i==0 else 'none',f'data-ring="{color}"'),f'标注颜色 {color}',f'data-color="{color}"')
    out+=text(224,34,'粗细',14,MUTED,extra='data-param-label="true"')
    for width,label,xx in [(2,'2 px',274),(4,'4 px',332),(8,'8 px',390)]:
        out+=option(xx,14,50,label,f'data-width="{width}"',width==4,visual_option('width',width))
    out+=text(454,35,'4 px',13,MUTED,extra='data-param-value="true"')
    line_options=text(16,91,'线型',14,MUTED)+option(58,69,56,'实线','data-dash="false"',True,visual_option('solid'))+option(120,69,56,'虚线','data-dash="true"',preview=visual_option('dashed'))
    out+='<g data-line-options="true">'+line_options+'</g>'
    arrow_options=text(200,91,'箭头',14,MUTED)
    for name,label,xx in [('filled','实心',246),('open','开口',326),('double','双头',406)]:
        arrow_options+=option(xx,69,72,label+'箭头',f'data-head="{name}"',name=='filled',visual_option(name))
    out+='<g data-arrow-options="true">'+arrow_options+'</g>'
    rect_options=text(200,91,'填充',14,MUTED)
    for name,label,xx in [('none','描边',246),('soft','半透',326),('solid','实心',406)]:
        rect_options+=option(xx,69,72,{'none':'描边','soft':'半透明填充','solid':'实心填充'}[name],f'data-fill="{name}"',name=='none',visual_option('fill-'+name))
    out+='<g data-rect-options="true" style="display:none">'+rect_options+'</g>'
    out+='<g data-text-options="true" style="display:none">'+option(16,69,80,'加粗','data-action="bold"')+option(106,69,80,'底色','data-action="text-bg"')+'</g>'
    return f'<g data-popover="true" transform="translate({anchor},716)" style="display:{"none" if selected=="pointer" else "inline"}">'+out+'</g>'


def annotate():
    return backdrop()+image_content(True)+crop()+mainbar(selected='arrow')


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
let current='capture', tool='pointer', markTool='arrow', color='#c64635', width=4, hasMark=false, canRedo=false, arrowHead='filled', dashed=false, rectFill='none', bold=false, textBackground=false;
const toolStyles={};
const hints={capture:'常用工具已在第一排。点击工具后，相关参数自动出现在它下方；调整后直接输出。',annotate:'箭头下方直接调整颜色、粗细、线型和箭头样式；这里尚不支持自由绘制。',selection:'固定选字示例；复制会尝试写入这段示例文字，尚未接入 OCR。',pin:'钉图操作栏的显现状态。网页未连接系统置顶窗口。',settings:'只演示两项设置；切换值不会更改 macOS。'};
const announce = message => { $('#status').textContent=message; };
function closeStyles() {
  $$('[data-popover]').forEach(el=>el.style.display='none');
}
function syncMarks() {
  $$('.scene [data-export-content]').forEach(group=>{
    if (!group.querySelector('[data-mark]')) {
      const source=$('[data-scene-id="annotate"] [data-export-content]');
      source.querySelectorAll('[data-mark]').forEach(mark=>group.append(mark.cloneNode(true)));
    }
    group.querySelectorAll('[data-mark]').forEach(mark=>{
      mark.style.display=mark.dataset.mark===markTool && hasMark?'inline':'none';
      mark.setAttribute('color',color); mark.setAttribute('stroke-width',mark.dataset.mark==='highlight'?width*4:width);
      const text=mark.querySelector('text');
      if(text) text.setAttribute('font-size',mark.dataset.mark==='number'?width*2+8:{2:18,4:24,8:32}[width]);
      if(mark.dataset.mark==='number') mark.querySelector('circle').setAttribute('r',width*2+8);
      if(mark.dataset.mark==='arrow'){
        mark.querySelector('[data-arrow-shaft]').setAttribute('stroke-dasharray',dashed?'12 8':'none');
        mark.querySelectorAll('[data-arrow-head]').forEach(head=>head.style.display=head.dataset.arrowHead===arrowHead?'inline':'none');
      }
      if(mark.dataset.mark==='rectangle'){
        const box=mark.querySelector('rect');box.setAttribute('stroke-dasharray',dashed?'12 8':'none');
        box.setAttribute('fill',rectFill==='none'?'none':'currentColor');box.setAttribute('fill-opacity',rectFill==='soft'?'.22':'1');
      }
      if(mark.dataset.mark==='text'){
        text.setAttribute('font-weight',bold?'700':'400');
        const bg=mark.querySelector('[data-text-background]');bg.style.display=textBackground?'inline':'none';
        const fontSize=Number(text.getAttribute('font-size')), measured=text.getBBox();
        const bounds=measured.width>0 && measured.height>0 ? measured : {x:Number(text.getAttribute('x')),y:Number(text.getAttribute('y'))-fontSize*.85,width:[...text.textContent].length*fontSize,height:fontSize};
        bg.setAttribute('x',bounds.x-6);bg.setAttribute('y',bounds.y-6);
        bg.setAttribute('width',bounds.width+12);bg.setAttribute('height',bounds.height+12);
      }

    });
  });
  $$('[data-tool]').forEach(el=>{
    const active=el.dataset.tool===tool;el.setAttribute('aria-pressed',active);
    el.querySelector('rect').setAttribute('fill',active?'#e6eee8':'transparent');
    el.querySelector('text')?.setAttribute('fill',active?'#285c53':'#282d2a');
    el.querySelectorAll('g[stroke]').forEach(icon=>icon.setAttribute('stroke',active?'#285c53':'#282d2a'));
  });
  for(const [name,enabled] of [['undo',hasMark],['redo',canRedo]]) {
    $$(`[data-action="${name}"]`).forEach(el=>{el.setAttribute('aria-disabled',String(!enabled));el.setAttribute('opacity',enabled?'1':'.35');});
  }
  const styleTool=tool==='pointer'?markTool:tool, covered=styleTool==='cover';
  const hasOptions=['arrow','rectangle','text'].includes(styleTool);
  $$('[data-popover]').forEach(panel=>{
    const scene=panel.closest('.scene');panel.style.display=tool!=='pointer' && scene.dataset.sceneId===current?'inline':'none';
    const active=scene.querySelector(`[data-tool="${tool}"] rect`);
    if(active)panel.setAttribute('transform',`translate(${active.getAttribute('x')},716)`);
    panel.querySelector('rect').setAttribute('width',covered?208:512);
    panel.querySelector('rect').setAttribute('height',hasOptions?116:60);
    panel.querySelector('[data-line-options]').style.display=['arrow','rectangle'].includes(styleTool)?'inline':'none';
    panel.querySelector('[data-arrow-options]').style.display=styleTool==='arrow'?'inline':'none';
    panel.querySelector('[data-rect-options]').style.display=styleTool==='rectangle'?'inline':'none';
    panel.querySelector('[data-text-options]').style.display=styleTool==='text'?'inline':'none';
    const label=panel.querySelector('[data-param-label]');label.style.display=covered?'none':'inline';
    label.textContent=styleTool==='text'?'字号':styleTool==='number'?'大小':'粗细';
    const value=panel.querySelector('[data-param-value]');value.style.display=['text','number','cover'].includes(styleTool)?'none':'inline';value.textContent=width+' px';
    panel.querySelectorAll('[data-width]').forEach((el,i)=>{
      el.style.display=covered?'none':'inline';
      const label=styleTool==='text'?['18','24','32'][i]:styleTool==='number'?['小','中','大'][i]:['2 px','4 px','8 px'][i];
      el.querySelector('text').textContent=label;
      const description=panel.querySelector('[data-param-label]').textContent+' '+label;
      el.setAttribute('aria-label',description);el.querySelector('title').textContent=description;
      el.querySelector('text').style.display=['text','number'].includes(styleTool)?'inline':'none';
      el.querySelector('[data-option-preview]').style.display=['text','number'].includes(styleTool)?'none':'inline';
    });
  });
  for(const [selector,key,value] of [['[data-width]','width',String(width)],['[data-head]','head',arrowHead],['[data-dash]','dash',String(dashed)],['[data-fill]','fill',rectFill]]) {
    $$(selector).forEach(el=>{const active=el.dataset[key]===value;el.setAttribute('aria-pressed',String(active));el.querySelector('rect').setAttribute('fill',active?'#e6eee8':'#fff');el.querySelector('text').setAttribute('fill',active?'#285c53':'#282d2a');el.querySelector('[data-option-preview]')?.setAttribute('color',active?'#285c53':'#282d2a');});
  }
  for(const [name,active] of [['bold',bold],['text-bg',textBackground]]){
    $$(`[data-action="${name}"]`).forEach(el=>{el.setAttribute('aria-pressed',String(active));el.querySelector('rect').setAttribute('fill',active?'#e6eee8':'#fff');});
  }
  $$('[data-ring]').forEach(el=>el.setAttribute('stroke',el.dataset.ring===color?'#285c53':'none'));

}
function show(scene) {
  current=scene; $$('.scene').forEach(el=>el.hidden=el.dataset.sceneId!==scene);
  $$('nav [data-scene]').forEach(el=>el.setAttribute('aria-pressed',el.dataset.scene===scene));
  if(scene==='annotate'){tool='arrow';markTool='arrow';hasMark=true;canRedo=false;}
  if(scene==='capture'||scene==='selection') tool='pointer';
  closeStyles();syncMarks();announce(hints[scene]);
}
function chooseTool(name) {
  if(current==='selection' && name!=='pointer')show('capture');
  if(tool!=='pointer')toolStyles[tool]={color,width};
  tool=name;
  if(name!=='pointer'){markTool=name;hasMark=true;canRedo=false;({color,width}=toolStyles[name] || {color:'#c64635',width:4});}
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
  if(el.getAttribute('aria-disabled')==='true')return;
  if(el.dataset.scene) return show(el.dataset.scene);
  if(el.dataset.tool) return chooseTool(el.dataset.tool);
  if(el.dataset.color) {color=el.dataset.color;return syncMarks();}
  if(el.dataset.width) {width=Number(el.dataset.width);return syncMarks();}
  if(el.dataset.head) {arrowHead=el.dataset.head;return syncMarks();}
  if(el.dataset.dash) {dashed=el.dataset.dash==='true';return syncMarks();}
  if(el.dataset.fill) {rectFill=el.dataset.fill;return syncMarks();}
  const name=el.dataset.action;
  if(name==='bold'){bold=!bold;syncMarks();return;}
  if(name==='text-bg'){textBackground=!textBackground;syncMarks();return;}
  if(name==='undo'){hasMark=false;canRedo=true;syncMarks();return;}
  if(name==='redo'){hasMark=true;canRedo=false;syncMarks();return;}
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
document.addEventListener('click',event=>{const el=event.target.closest('[data-scene],[data-tool],[data-color],[data-width],[data-head],[data-dash],[data-fill],[data-action]');if(el) activate(el);});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape' && tool!=='pointer') {chooseTool('pointer');return;}
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
