#!/usr/bin/env python3
"""生成独立 SVG 设计画板和不依赖网络的网页试稿；不修改原生 App。"""
from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parent
FONT = "'Helvetica Neue', 'PingFang SC', 'Microsoft YaHei', sans-serif"
INK, MUTED, BLUE = '#292c32', '#747981', '#087ff5'


def rect(x, y, w, h, fill, r=0, stroke='none', extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" {extra}/>'


def text(x, y, value, size=14, color=INK, weight=400, extra=''):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" font-weight="{weight}" {extra}>{escape(str(value))}</text>'


def line(x1, y1, x2, y2, color='#dddfe3', width=1, extra=''):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" {extra}/>'


def circle(x, y, r, fill, stroke='none', extra=''):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" {extra}/>'


PATHS = {
    'pointer': '<path d="M5 3l14 10-7 1-3 7z"/>',
    'rectangle': '<rect x="4" y="5" width="16" height="14" rx="2"/>',
    'ellipse': '<ellipse cx="12" cy="12" rx="8" ry="7"/>',
    'arrow': '<path d="M5 19L19 5M9 5h10v10"/>',
    'line': '<path d="M5 19L19 5"/>',
    'pencil': '<path d="M4 20l1-6L16 3l5 5L10 19zM14 5l5 5M5 14l5 5"/>',
    'text': '<path d="M4 6V4h16v2M12 4v16M8 20h8"/>',
    'mosaic': '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"/>',
    'highlight': '<path d="M5 14l8-9 6 5-8 9zM4 20h8M13 5l2-2 6 5-2 2"/>',
    'number': '<circle cx="12" cy="12" r="9"/><path d="M10 9l2-2v10M10 17h4"/>',
    'undo': '<path d="M9 5L4 10l5 5M4 10h9a7 7 0 016 10"/>',
    'redo': '<path d="M15 5l5 5-5 5M20 10h-9a7 7 0 00-6 10"/>',
    'copy': '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M15 5V3H3v12h2"/>',
    'save': '<path d="M12 3v12m-5-5l5 5 5-5M4 16v5h16v-5"/>',
    'close': '<path d="M6 6l12 12M18 6L6 18"/>',
    'check': '<path d="M5 12l5 5L20 7"/>',
    'pin': '<path d="M8 3h8l-1 7 4 4H5l4-4zM12 14v8"/>',
    'beauty': '<rect x="3" y="3" width="18" height="18" rx="4"/><rect x="7" y="7" width="10" height="10" rx="1"/>',
    'ai': '<path d="M12 2l2.8 7.2L22 12l-7.2 2.8L12 22l-2.8-7.2L2 12l7.2-2.8z"/>',
    'key': '<circle cx="8" cy="9" r="5"/><path d="M12 13l8 8M16 17l3-3M18 19l3-3"/>',
    'chevron': '<path d="M7 10l5 5 5-5"/>',
    'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3M4 4l2 2M18 18l2 2M4 20l2-2M18 6l2-2"/>',
    'warning': '<path d="M12 3L2 21h20zM12 9v5M12 17v1"/>',
    'gear': '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/>',
    'folder': '<path d="M3 7V4h7l2 3h9v13H3z"/>',
    'minus': '<path d="M5 12h14"/>',
    'plus': '<path d="M5 12h14M12 5v14"/>',
}


def icon(name, x, y, size=20, color=INK):
    return f'<g transform="translate({x},{y}) scale({size/24})" fill="none" stroke="{color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{PATHS[name]}</g>'


def action(content, label, attrs='', disabled=False):
    if disabled:
        attrs += ' aria-disabled="true" opacity=".38"'
    else:
        attrs += ' tabindex="0"'
    return f'<g role="button" aria-label="{escape(label)}" {attrs}><title>{escape(label)}</title>{content}</g>'


def button(x, y, w, label, action_name='', primary=False, disabled=False, symbol=None):
    color = 'white' if primary else INK
    body = rect(x,y,w,32,BLUE if primary else '#fff',7,'none' if primary else '#dedfe2')
    if symbol:
        body += icon(symbol,x+10,y+7,17,color)
    body += text(x+w/2+(8 if symbol else 0),y+21,label,13,color,500,'text-anchor="middle"')
    return action(body, label + ('（设计试稿暂未接入）' if disabled else ''), f'data-action="{action_name}"', disabled)


def panel(x,y,w,h,r=12,fill='#f8f8fa'):
    return rect(x,y,w,h,fill,r,'#cdd0d5','filter="url(#shadow)"') + rect(x+.5,y+.5,w-1,h-1,'none',r,'#ffffffb3')


def dots(x,y):
    return ''.join(circle(x+i*20,y,5.7,c,'#00000012') for i,c in enumerate(['#ff6058','#febd2e','#29c840']))


def defs():
    palettes=[('#fde2c8','#bc8eb7','#6076b7'),('#d8ecfd','#7cb7e8','#5365a0'),('#d7ebdf','#8fb8a4','#587c82'),('#fbe2cd','#dfad91','#b36768'),('#eadcf5','#ab91cf','#5f6cb5'),('#f5e5ac','#c3bc86','#839980'),('#dbe6ee','#a1afbf','#747e97'),('#f4cee0','#ce89ad','#ac658b')]
    result = '<defs><linearGradient id="desktop" x2=".95" y2="1"><stop stop-color="#cbd8dd"/><stop offset=".48" stop-color="#bac5d7"/><stop offset="1" stop-color="#9dacc8"/></linearGradient><linearGradient id="hill" x2="1" y2="1"><stop stop-color="#789789"/><stop offset="1" stop-color="#365c54"/></linearGradient><filter id="shadow" x="-40%" y="-50%" width="180%" height="230%"><feDropShadow dx="0" dy="10" stdDeviation="16" flood-color="#22324f" flood-opacity=".18"/></filter><filter id="softshadow" x="-40%" y="-50%" width="180%" height="230%"><feDropShadow dx="0" dy="14" stdDeviation="12" flood-color="#2b2344" flood-opacity=".22"/></filter>'
    for i,(a,b,c) in enumerate(palettes):
        result += f'<linearGradient id="bg{i}" x2="1" y2="1"><stop stop-color="{a}"/><stop offset=".48" stop-color="{b}"/><stop offset="1" stop-color="{c}"/></linearGradient>'
    return result+'</defs>'


def desktop():
    return rect(0,0,1440,900,'url(#desktop)') + '<path d="M-140 720C330 120 850 440 1570 0V900H-140Z" fill="#dce3ea" opacity=".3"/><path d="M-50 1000C500 160 890 1040 1510 200V1000Z" fill="#8c9fbf" opacity=".2"/>' + rect(0,0,1440,32,'#f6f8fb85') + text(24,22,'●',16,INK) + text(58,22,'备忘录',13,INK,600) + text(128,22,'文件',13) + text(178,22,'编辑',13) + text(228,22,'显示',13) + icon('pin',1202,8,17) + text(1242,22,'周二  11月3日  11:03',12)


def note(x=0,y=0,scale=1):
    body = rect(0,0,680,420,'#fffdf9')
    body += text(36,34,'工作手记  /  本周',12,'#94897e')
    body += text(36,84,'把想法，留在眼前。',28,'#34352f',600)
    body += text(36,124,'把重要的决定留下来，',17,'#565a53')
    body += text(36,153,'然后继续做手头的事。',17,'#565a53')
    body += line(36,179,642,179,'#e9e4dc')
    body += text(36,216,'这一周，做好三件事',15,'#3e4740',600)
    tasks=['把讨论里的结论整理成一页。','把关键步骤截图，标出需要改的地方。','留出一个下午，完成最想做的小项目。']
    for i,s in enumerate(tasks):
        yy=251+i*41
        body += rect(36,yy-13,14,14,'#fffdf9',3,'#b3b8ac') + text(62,yy,s,15,'#565d55')
    body += text(36,391,'周末去走走。让脑袋也透一口气。',13,'#94988d')
    body += '<g transform="translate(476,48)"><rect width="166" height="105" rx="10" fill="#ede7d9"/><circle cx="125" cy="28" r="14" fill="#d3a370"/><path d="M0 76Q44 27 93 73T166 68V105H0Z" fill="#a4b7a2"/><path d="M0 105Q68 46 166 94V105Z" fill="url(#hill)"/></g>'
    return f'<g transform="translate({x},{y}) scale({scale})">{body}</g>'


def notes_window():
    out=panel(236,115,968,579,13,'#fffdf9')+dots(258,135)
    out+=rect(237,156,179,537,'#f4f2ed')+line(237,155,1203,155,'#e0dfda')
    out+=icon('folder',259,182,20,'#a4947f')+text(289,198,'我的笔记',14,'#615f57',600)
    out+=rect(249,220,154,34,'#e4e1da',7)+text(267,242,'工作手记',13,'#44483e',500)
    out+=text(267,282,'阅读摘录',13,'#7e8076')+text(267,322,'周末计划',13,'#7e8076')
    out+=text(690,140,'工作手记',12,'#7b7d74',500,'text-anchor="middle"')
    out+=note(452,202)
    return out


def crop_frame():
    x,y,w,h=434,187,716,450
    out=f'<path d="M0 32H1440V900H0Z M{x} {y}V{y+h}H{x+w}V{y}Z" fill="#172237" opacity=".28" fill-rule="evenodd"/>'
    out+=rect(x,y,w,h,'none',0,'#fff','stroke-width="1.5"')
    for xx,yy in [(x,y),(x+w/2,y),(x+w,y),(x,y+h/2),(x+w,y+h/2),(x,y+h),(x+w/2,y+h),(x+w,y+h)]:
        out+=rect(xx-3.5,yy-3.5,7,7,'white',1,'#7791b6')
    out+=rect(x,y-29,116,22,'#28313edb',5)+text(x+9,y-14,'1432 × 900 px',11,'white',500)
    return out


TOOLS=[('pointer','选择','V'),('rectangle','矩形','R'),('ellipse','椭圆','O'),('arrow','箭头','A'),('line','直线','L'),('pencil','画笔','P'),('text','文字','T'),('mosaic','马赛克','M'),('highlight','高亮','H'),('number','序号','N')]


def toolbar(y=672, selected='arrow'):
    x=310
    out=panel(x,y,840,50,11)
    for i,(name,label,key) in enumerate(TOOLS):
        xx=x+9+i*36
        body=rect(xx,y+8,32,34,BLUE if name==selected else 'transparent',7,extra=f'data-tool-bg="{name}"')+icon(name,xx+6,y+15,21,'white' if name==selected else '#4e5258')
        out+=action(body,f'{label}（{key}）',f'data-tool="{name}" aria-pressed="{str(name==selected).lower()}"')
    out+=line(x+375,y+12,x+375,y+38,'#d4d6da')
    out+=action(icon('undo',x+389,y+15,20),'撤销（设计试稿暂未接入）',disabled=True)
    out+=action(icon('redo',x+425,y+15,20),'重做（设计试稿暂未接入）',disabled=True)
    out+=line(x+458,y+12,x+458,y+38,'#d4d6da')
    for pos,name,label,scene in [(472,'beauty','美化（B）','beauty'),(512,'ai','问 AI（⌘J）','ai'),(552,'pin','钉图（F3）','pin')]:
        out+=action(rect(x+pos-3,y+8,34,34,'transparent',7)+icon(name,x+pos+4,y+15,21),label,f'data-scene="{scene}"')
    out+=line(x+595,y+12,x+595,y+38,'#d4d6da')
    out+=button(x+608,y+9,68,'保存',disabled=True)
    out+=button(x+686,y+9,94,'复制',primary=True,disabled=True,symbol='copy')
    out+=action(icon('close',x+800,y+15,20),'返回框选', 'data-scene="capture"')
    return out


def stylebar():
    x,y=448,734
    out=panel(x,y,564,48,10)+text(x+16,y+30,'箭头',13,'#50555d',500,'data-tool-label="true"')
    for i,c in enumerate(['#f45c59','#f2ae38','#54b879','#1887f5','#9c72da','#31373e']):
        cx=x+82+i*28
        out+=action(circle(cx,y+24,9,c)+circle(cx,y+24,12,'none',BLUE if i==0 else 'none',f'data-swatch-ring="{c}"'),'标注颜色 '+c,f'data-color="{c}"')
    out+=line(x+250,y+11,x+250,y+37)
    out+=text(x+264,y+30,'粗细',12,MUTED,400,'data-width-label="true"')
    for i,width in enumerate([2,4,6]):
        xx=x+300+i*40
        body=rect(xx,y+10,34,28,'#e2ecf8' if width==4 else '#f8f8fa',5,extra=f'data-width-bg="{width}"')+line(xx+8,y+24,xx+26,y+24,'#4b525c',width,'stroke-linecap="round" data-weight-line="true"')+text(xx+17,y+28,'',11,INK,500,'text-anchor="middle" data-weight-number="true"')
        out+=action(body,f'{width} 像素',f'data-width="{width}"')
    out+=line(x+427,y+11,x+427,y+37)
    out+=action(rect(x+438,y+10,107,28,'#fff',5,'#dedfe2')+text(x+454,y+29,'实线',12,INK,400,'data-dash-label="true"')+icon('chevron',x+519,y+16,15),'切换实线或虚线','data-action="dash"')
    return out


def annotations():
    shapes={
        'pointer':'',
        'arrow':'<path d="M966 524Q923 472 841 490M853 481l-12 9 15 2" fill="none"/>',
        'rectangle':'<rect x="508" y="479" width="328" height="32" rx="4" fill="none"/>',
        'ellipse':'<ellipse cx="671" cy="494" rx="170" ry="29" fill="none"/>',
        'line':'<path d="M513 508H835"/>',
        'pencil':'<path d="M512 511Q555 501 587 511T661 509T738 511T832 507" fill="none"/>',
        'text':'<text x="904" y="489" font-size="20" stroke="none" fill="currentColor">这里补图</text>',
        'mosaic':''.join(rect(513+a*16,479+b*16,16,16,['#bfc4bd','#dce0d7','#969e93'][(a+b)%3]) for a in range(20) for b in range(2)),
        'highlight':'<path d="M513 489H834" stroke-width="20" opacity=".3"/>',
        'number':'<circle cx="490" cy="493" r="14" fill="currentColor" stroke="none"/><text x="490" y="499" text-anchor="middle" fill="white" stroke="none" font-size="16" font-weight="600">1</text>',
    }
    out=''
    for name,shape in shapes.items():
        out+=f'<g data-annotation="{name}" color="#f45c59" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" style="display:{"inline" if name=="arrow" else "none"}">{shape}</g>'
    return out


def annotate():
    return desktop()+notes_window()+crop_frame()+annotations()+toolbar()+stylebar()


def capture():
    out=desktop()+notes_window()+crop_frame()
    x,y=1150,535
    out+=panel(x,y,126,136,10,'#fff')
    for a in range(10):
        for b in range(8):
            out+=rect(x+8+a*11,y+8+b*11,11,11,['#fffdf9','#e7e4db','#a6b19e'][(a*3+b*7)%3] if 3<a<7 else '#fffdf9')
    out+=line(x+63,y+8,x+63,y+96,BLUE,1)+line(x+8,y+52,x+118,y+52,BLUE,1)
    out+=rect(x+58,y+47,11,11,'none',0,BLUE)+text(x+63,y+119,'#FFFDF9',11,INK,500,'text-anchor="middle"')
    out+=panel(520,674,552,52,11)
    out+=text(538,706,'区域截图',13,INK,500)+line(616,687,616,713)
    out+=text(633,706,'1432 × 900 px',13,MUTED)+button(782,684,105,'重新框选','reset')
    out+=button(899,684,155,'开始标注','annotate',True,symbol='check')
    return out


def selection():
    out=desktop()+notes_window()+crop_frame()
    out+=rect(486,306,155,25,'#b1d3fb',2)+text(488,326,'把重要的决定留下来',17,'#354d6d')
    out+=line(641,304,641,331,'#236bba',1.4)+toolbar(selected='pointer')
    out+=panel(525,734,430,48,10)+text(543,764,'已选 9 字',12,MUTED)+button(634,742,130,'复制文字','copy-text',symbol='copy')+button(775,742,163,'问 AI','ai',symbol='ai')
    return out


def pinned():
    out=desktop()+notes_window()
    out+=rect(0,32,1440,868,'#385070',0,extra='opacity=".12"')
    out+='<g data-pin-image="true">'+panel(848,172,476,329,9,'#fffdf9')+note(856,182,.675)+'</g>'
    out+=panel(847,513,478,48,10)
    out+=action(rect(855,520,34,32,'transparent',6)+icon('close',862,526,20),'关闭示例钉图','data-scene="annotate"')
    out+=button(898,521,74,'选字','selection')+button(980,521,74,'标注','annotate')
    out+=line(1066,525,1066,549)+action(icon('minus',1080,527,18),'缩小示例','data-action="pin-smaller"')
    out+=text(1143,544,'100%',12,INK,400,'text-anchor="middle" data-pin-zoom="true"')
    out+=action(icon('plus',1184,527,18),'放大示例','data-action="pin-larger"')
    out+=line(1217,525,1217,549)+action(icon('copy',1240,526,20),'复制图片（设计试稿暂未接入）',disabled=True)+action(icon('save',1283,526,20),'保存图片（设计试稿暂未接入）',disabled=True)
    return out


def slider(y,label,value,name):
    x=151
    return text(x,y,label,12,'#636973')+text(x+194,y,str(value),12,INK,500,f'text-anchor="end" data-slider-label="{name}"')+f'<g role="slider" tabindex="0" aria-label="{label}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{value}" data-slider="{name}">'+rect(x,y+15,194,4,'#d5d8de',2)+rect(x,y+15,194*value/100,4,BLUE,2,f'none',f'data-slider-fill="{name}"')+circle(x+194*value/100,y+17,7,'#fff','#b5bdc9',f'data-slider-knob="{name}"')+'</g>'


def beauty():
    out=desktop()+panel(115,88,1210,731,14,'#f5f5f7')+dots(139,113)+text(248,118,'ccShot',14,INK,600)
    out+=line(116,141,1324,141,'#d7d9dd')+line(378,142,378,773,'#d7d9dd')
    out+=button(1018,97,92,'返回标注','annotate')+button(1120,97,82,'保存',disabled=True)+button(1212,97,92,'复制',primary=True,disabled=True)
    out+=text(151,181,'背景',15,INK,600)
    for i in range(8):
        x,y=151+(i%4)*48,201+(i//4)*50
        out+=action(rect(x,y,39,39,f'url(#bg{i})',9)+rect(x-3,y-3,45,45,'none',11,BLUE if i==0 else 'none',f'data-background-ring="{i}" stroke-width="2"'),f'渐变背景 {i+1}',f'data-background="{i}"')
    out+=text(151,326,'纯色',12,MUTED)
    for i,c in enumerate(['#fffdf9','#2d343d','#e8ddcd','#b7cbc6','#c0b9d7','#d1a38e']):
        out+=action(circle(162+i*33,350,10,c,'#00000012'),'纯色背景 '+c,f'data-background-color="{c}"')
    out+=button(151,378,194,'导入图片',disabled=True,symbol='plus')
    out+=line(151,433,345,433)+text(151,462,'画布比例',12,MUTED)
    for i,v in enumerate(['16:9','4:3','1:1','9:16','自由']):
        x=149+i*40
        out+=action(rect(x,478,38,28,'#e0ebfa' if i==0 else '#edeef0',5,extra=f'data-ratio-bg="{v}"')+text(x+19,497,v,11,BLUE if i==0 else '#656c75',500,'text-anchor="middle"'),v,f'data-ratio="{v}"')
    out+=slider(548,'内边距',34,'padding')+slider(612,'圆角',30,'radius')+slider(676,'阴影',40,'shadow')
    out+=rect(403,205,896,504,'url(#bg0)',0,extra='data-beauty-background="true"')
    out+='<g data-beauty-image="true" transform="translate(579,289) scale(.8)" filter="url(#softshadow)"><clipPath id="beautyclip"><rect width="680" height="420" rx="12" data-beauty-clip="true"/></clipPath><g clip-path="url(#beautyclip)">'+note()+'</g></g>'
    out+=line(116,774,1324,774,'#d7d9dd')+text(150,802,'100%',12,MUTED)+text(850,802,'1920 × 1080 px',12,MUTED,500,'text-anchor="middle" data-dimensions="true"')
    out+=action(icon('pin',1281,786,20),'预览钉图','data-scene="pin"')
    return out


def ai():
    out=desktop()+notes_window()+rect(0,32,1440,868,'#15243d',extra='opacity=".18"')
    out+=panel(174,218,720,454,8,'#fffdf9')+note(194,233)
    out+=panel(919,140,348,617,13,'#fafafa')+icon('ai',940,161,20,BLUE)+text(970,178,'问 AI',15,INK,600)
    out+=action(icon('close',1233,161,18),'返回标注','data-scene="annotate"')+line(920,199,1266,199)
    out+=rect(945,220,296,55,'#f1f2f4',8)+icon('beauty',959,236,22,'#747b85')+text(993,243,'当前截图',13,INK,500)+text(993,262,'1432 × 900 px',11,MUTED)
    out+=rect(1063,325,60,60,'#e8eef6',17)+icon('key',1079,341,28,'#6885a8')
    out+=text(1093,421,'连接你自己的 AI',20,INK,600,'text-anchor="middle"')
    out+=text(1093,453,'设置服务与 API Key 后发送截图。',13,MUTED,400,'text-anchor="middle"')
    out+=button(1018,482,150,'前往设置','settings',True)
    out+=line(945,568,1241,568)+text(945,595,'快捷提问',12,MUTED)
    for i,(label,w) in enumerate([('解释',62),('翻译',62),('总结',62),('提取表格',90)]):
        x=945+sum([62,62,62,90][:i])+i*6
        out+=button(x,611,w,label,disabled=True)
    out+=rect(944,669,298,61,'#f1f2f4',9)+text(959,704,'先连接 AI 服务',13,'#a0a5ad')+icon('arrow',1209,690,21,'#adb3bc')
    return out


def toggle(x,y,active=False):
    return rect(x,y,34,20,BLUE if active else '#c8ccd2',10)+circle(x+(24 if active else 10),y+10,8,'white')


def settings():
    out=desktop()+rect(0,32,1440,868,'#34435e',extra='opacity=".08"')+panel(391,90,658,722,14,'#f7f7f9')
    out+=dots(414,115)+text(720,120,'ccShot 设置',14,INK,600,'text-anchor="middle"')+line(392,140,1048,140,'#d7d9de')
    out+=text(422,179,'快捷键',13,'#555c66',600)+rect(416,192,608,129,'white',9,'#e1e3e7')
    for i,(name,key) in enumerate([('开始截图','F1'),('钉住截图 / 剪贴板','F3'),('备选截图快捷键','⌃ ⌥ S')]):
        yy=220+i*41
        out+=text(435,yy,name,13)+rect(918,yy-20,87,28,'#f5f6f8',5,'#e4e6e9')+text(961,yy,key,13,'#525965',500,'text-anchor="middle"')
        if i<2: out+=line(435,yy+12,1005,yy+12,'#eeeff2')
    out+=text(423,347,'F1 被系统占用时，使用 Fn + F1 或备选快捷键。',12,MUTED)
    out+=text(422,385,'截图',13,'#555c66',600)+rect(416,399,608,92,'white',9,'#e1e3e7')
    out+=text(435,429,'保存位置',13)+text(940,429,'每次询问',13,MUTED,400,'text-anchor="end"')+action(icon('folder',978,413,19),'选择保存位置（设计试稿暂未接入）',disabled=True)+line(435,444,1005,444,'#eeeff2')
    out+=text(435,475,'截图后直接选字',13)+toggle(968,458,True)
    out+=text(422,530,'通用',13,'#555c66',600)+rect(416,543,608,92,'white',9,'#e1e3e7')
    out+=text(435,574,'登录时启动',13)+action(toggle(968,556), '登录启动开关（仅切换试稿外观）','data-action="toggle-login"')+line(435,589,1005,589,'#eeeff2')
    out+=text(435,620,'屏幕录制权限',13)+icon('warning',843,605,16,'#a87b36')+text(865,620,'未授权示例',12,'#986f33')+button(947,596,61,'打开',disabled=True)
    out+=text(422,674,'AI 服务',13,'#555c66',600)+rect(416,688,608,60,'white',9,'#e1e3e7')+icon('key',435,707,20,'#6a7689')+text(470,721,'尚未配置',13,MUTED)+button(892,702,113,'配置服务',disabled=True)
    return out


SCENES=[('annotate','标注',annotate),('capture','框选',capture),('selection','选字',selection),('pin','钉图',pinned),('beauty','美化',beauty),('ai','问 AI',ai),('settings','设置',settings)]


def svg(scene,label,content):
    result=f'<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900" role="img" aria-label="ccShot {label}设计试稿" style="font-family:{FONT}"><title>ccShot · {label} · 示例画面</title>'+defs()+content+'</svg>'
    # 每块画板的资源 ID 独立，嵌入同一页面不会误用别的画板渐变或裁切。
    import re
    ids=re.findall(r'id="([^"]+)"',result)
    for identifier in ids:
        result=result.replace(f'id="{identifier}"',f'id="{scene}-{identifier}"').replace(f'url(#{identifier})',f'url(#{scene}-{identifier})')
    return result


SCRIPT=r'''
const scenes = [...document.querySelectorAll('.scene')];
let current = 'annotate', currentTool = 'arrow', dashed = false, login = false, pinZoom = 1;
const toolNames = {pointer:'选择',rectangle:'矩形',ellipse:'椭圆',arrow:'箭头',line:'直线',pencil:'画笔',text:'文字',mosaic:'马赛克',highlight:'高亮',number:'序号'};
const hints = {annotate:'点击工具、颜色或粗细，查看标注样式。',capture:'点击「开始标注」进入截图后的操作。',selection:'选择高亮为示例；「复制文字」会复制这段示例文本。',pin:'这里展示钉图外观；尚未连接系统置顶窗口。',beauty:'点击背景、比例，拖动滑块查看变化。',ai:'未配置状态；不会发送图片或请求模型。',settings:'设置效果仅保留在当前预览，不更改系统。'};
function show(name) {
  if (!scenes.some(s=>s.dataset.sceneId===name)) return;
  current=name;
  scenes.forEach(s=>s.hidden=s.dataset.sceneId!==name);
  document.querySelectorAll('nav button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.scene===name)));
  document.getElementById('hint').textContent=hints[name];
}
function status(message) { document.getElementById('hint').textContent=message; }
function scene() { return document.querySelector(`[data-scene-id="${current}"]`); }
function chooseTool(name) {
  currentTool=name;
  scene().querySelectorAll('[data-tool]').forEach(t=>{
    const on=t.dataset.tool===name;
    t.setAttribute('aria-pressed',String(on));
    t.querySelector('[data-tool-bg]').setAttribute('fill',on?'#087ff5':'transparent');
    t.querySelector('g[stroke]').setAttribute('stroke',on?'white':'#4e5258');
  });
  scene().querySelectorAll('[data-annotation]').forEach(n=>n.style.display=n.dataset.annotation===name?'inline':'none');
  const label=scene().querySelector('[data-tool-label]');
  if(label) label.textContent=toolNames[name];
  const numeric={text:['字号',[18,24,32]],mosaic:['颗粒',[8,12,18]],highlight:['透明度',['20%','35%','50%']],number:['起始号',[1,2,3]]}[name];
  scene().querySelector('[data-width-label]').textContent=numeric?numeric[0]:'粗细';
  scene().querySelectorAll('[data-width]').forEach((button,index)=>{
    button.querySelector('[data-weight-line]').style.display=numeric?'none':'inline';
    button.querySelector('[data-weight-number]').textContent=numeric?numeric[1][index]:'';
    button.setAttribute('aria-label',numeric?`${numeric[0]} ${numeric[1][index]}`:`${[2,4,6][index]} 像素`);
  });
  const dash=scene().querySelector('[data-action="dash"]');
  dash.setAttribute('aria-disabled',String(Boolean(numeric)));
  dash.setAttribute('opacity',numeric?'.38':'1');
  scene().querySelector('[data-dash-label]').textContent=numeric?'实线':(dashed?'虚线':'实线');
  status(`正在预览${toolNames[name]}工具；画板里的标记是样式示例。`);
}
const beautyState={padding:34,radius:30,shadow:40,ratio:'16:9'};
function updateBeauty() {
  const board=document.querySelector('[data-scene-id="beauty"]');
  const ratio=({'16:9':16/9,'4:3':4/3,'1:1':1,'9:16':9/16,'自由':680/420})[beautyState.ratio];
  const height=Math.min(504,896/ratio), width=height*ratio, x=851-width/2,y=457-height/2;
  const bg=board.querySelector('[data-beauty-background]');
  Object.entries({x,y,width,height}).forEach(([k,v])=>bg.setAttribute(k,v));
  const scale=Math.min(width/680,height/420)*(1-beautyState.padding*.008);
  board.querySelector('[data-beauty-image]').setAttribute('transform',`translate(${851-340*scale},${457-210*scale}) scale(${scale})`);
  board.querySelector('[data-beauty-clip]').setAttribute('rx',beautyState.radius*.4);
  const shadow=board.querySelector('#beauty-softshadow feDropShadow');
  shadow.setAttribute('stdDeviation',beautyState.shadow*.3);
  shadow.setAttribute('flood-opacity',beautyState.shadow*.006);
  const dimensions={'16:9':'1920 × 1080 px','4:3':'1440 × 1080 px','1:1':'1080 × 1080 px','9:16':'1080 × 1920 px','自由':'按截图与内边距调整'};
  board.querySelector('[data-dimensions]').textContent=dimensions[beautyState.ratio];
}
function setSlider(node,value) {
  value=Math.max(0,Math.min(100,Math.round(value)));
  const name=node.dataset.slider;
  beautyState[name]=value;
  node.setAttribute('aria-valuenow',value);
  const board=node.closest('svg');
  board.querySelector(`[data-slider-label="${name}"]`).textContent=value;
  board.querySelector(`[data-slider-fill="${name}"]`).setAttribute('width',194*value/100);
  board.querySelector(`[data-slider-knob="${name}"]`).setAttribute('cx',151+194*value/100);
  updateBeauty();
}
document.addEventListener('click',async event=>{
  const node=event.target.closest('[data-scene],[data-action],[data-tool],[data-color],[data-width],[data-background],[data-background-color],[data-ratio]');
  if(!node || node.getAttribute('aria-disabled')==='true') return;
  if(node.dataset.scene) {show(node.dataset.scene);return;}
  if(node.dataset.tool) {
    if(node.dataset.tool==='pointer') {show('selection');return;}
    if(current!=='annotate') show('annotate');
    chooseTool(node.dataset.tool);return;
  }
  if(node.dataset.color) {
    scene().querySelectorAll('[data-annotation]').forEach(a=>a.setAttribute('color',node.dataset.color));
    scene().querySelectorAll('[data-swatch-ring]').forEach(a=>a.setAttribute('stroke',a.dataset.swatchRing===node.dataset.color?'#087ff5':'none'));
  }
  if(node.dataset.width) {
    const index=[2,4,6].indexOf(Number(node.dataset.width));
    const annotation=scene().querySelector(`[data-annotation="${currentTool}"]`);
    if(currentTool==='text') annotation.querySelector('text').setAttribute('font-size',[18,24,32][index]);
    else if(currentTool==='highlight') annotation.querySelector('path').setAttribute('opacity',[.2,.35,.5][index]);
    else if(currentTool==='number') annotation.querySelector('text').textContent=index+1;
    else if(currentTool==='mosaic') {
      // 样式示例改变颗粒排布，不处理用户图片。
      const step=[8,12,18][index];
      annotation.replaceChildren();
      for(let x=0;x<320;x+=step)for(let y=0;y<32;y+=step){
        const pixel=document.createElementNS('http://www.w3.org/2000/svg','rect');
        Object.entries({x:513+x,y:479+y,width:Math.min(step,320-x),height:Math.min(step,32-y),fill:['#bfc4bd','#dce0d7','#969e93'][Math.round((x+y)/step)%3],stroke:'none'}).forEach(([k,v])=>pixel.setAttribute(k,v));
        annotation.append(pixel);
      }
    } else annotation.setAttribute('stroke-width',node.dataset.width);
    scene().querySelectorAll('[data-width-bg]').forEach(a=>a.setAttribute('fill',a.dataset.widthBg===node.dataset.width?'#e2ecf8':'#f8f8fa'));
  }
  if(node.dataset.background!==undefined || node.dataset.backgroundColor) {
    const color=node.dataset.backgroundColor || `url(#beauty-bg${node.dataset.background})`;
    scene().querySelector('[data-beauty-background]').setAttribute('fill',color);
    scene().querySelectorAll('[data-background-ring]').forEach(a=>a.setAttribute('stroke',a.dataset.backgroundRing===node.dataset.background?'#087ff5':'none'));
  }
  if(node.dataset.ratio) {
    beautyState.ratio=node.dataset.ratio;
    scene().querySelectorAll('[data-ratio-bg]').forEach(a=>a.setAttribute('fill',a.dataset.ratioBg===node.dataset.ratio?'#e0ebfa':'#edeef0'));
    updateBeauty();
  }
  switch(node.dataset.action) {
    case 'annotate': case 'selection': case 'beauty': case 'ai': case 'settings': show(node.dataset.action);break;
    case 'reset': show('capture');status('已回到框选示例；此处不读取桌面。');break;
    case 'dash':
      dashed=!dashed;
      scene().querySelectorAll('[data-annotation]').forEach(a=>a.setAttribute('stroke-dasharray',dashed?'8 7':'none'));
      scene().querySelector('[data-dash-label]').textContent=dashed?'虚线':'实线';break;
    case 'copy-text':
      try {await navigator.clipboard.writeText('把重要的决定留下来');status('已复制示例文字：把重要的决定留下来');}
      catch {status('浏览器未允许剪贴板写入；可手动复制示例：把重要的决定留下来');}break;
    case 'toggle-login':
      login=!login;node.querySelector('rect').setAttribute('fill',login?'#087ff5':'#c8ccd2');node.querySelector('circle').setAttribute('cx',968+(login?24:10));
      status('仅切换开关外观，未更改系统登录项。');break;
    case 'pin-smaller': case 'pin-larger':
      pinZoom=Math.min(1.2,Math.max(.6,pinZoom+(node.dataset.action==='pin-larger'?.1:-.1)));
      scene().querySelector('[data-pin-image]').setAttribute('transform',`translate(${1086*(1-pinZoom)},${336*(1-pinZoom)}) scale(${pinZoom})`);
      scene().querySelector('[data-pin-zoom]').textContent=Math.round(pinZoom*100)+'%';break;
  }
});
document.addEventListener('keydown',event=>{
  const slider=event.target.closest('[data-slider]');
  if(slider && ['ArrowLeft','ArrowRight'].includes(event.key)) {
    event.preventDefault();setSlider(slider,Number(slider.getAttribute('aria-valuenow'))+(event.key==='ArrowRight'?1:-1));return;
  }
  if((event.key==='Enter'||event.key===' ') && event.target.matches('g[role="button"][tabindex]')) {
    event.preventDefault();event.target.dispatchEvent(new MouseEvent('click',{bubbles:true}));
  }
});
document.querySelectorAll('[data-slider]').forEach(node=>{
  function move(event) {
    const svg=node.closest('svg'),point=svg.createSVGPoint();point.x=event.clientX;point.y=event.clientY;
    const local=point.matrixTransform(svg.getScreenCTM().inverse());setSlider(node,(local.x-151)/194*100);
  }
  node.addEventListener('pointerdown',event=>{event.preventDefault();node.setPointerCapture(event.pointerId);move(event);});
  node.addEventListener('pointermove',event=>{if(node.hasPointerCapture(event.pointerId))move(event);});
  node.addEventListener('pointerup',event=>{if(node.hasPointerCapture(event.pointerId))node.releasePointerCapture(event.pointerId);});
});
show('annotate');
'''


def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    nav,boards=[],[]
    for i,(name,label,render) in enumerate(SCENES):
        drawing=svg(name,label,render())
        (ROOT/f'{name}.svg').write_text(drawing,encoding='utf-8')
        nav.append(f'<button data-scene="{name}" aria-pressed="{str(i==0).lower()}">{label}</button>')
        interactive=drawing.replace('role="img"','role="group"')
        boards.append(f'<section class="scene" data-scene-id="{name}" {"hidden" if i else ""}>{interactive}</section>')
    html='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>ccShot · 界面试稿 v2</title><style>
*{box-sizing:border-box}body{margin:0;background:#edeef1;color:#292c32;font:14px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;min-width:1000px}header{height:74px;padding:0 32px;display:flex;align-items:center;gap:18px;background:#fff;border-bottom:1px solid #dddfe4}.brand{display:flex;align-items:center;gap:10px;font-size:19px;font-weight:650;letter-spacing:-.5px}.brand svg{width:28px;height:28px}.draft{font-size:12px;font-weight:400;letter-spacing:0;color:#747981;border-left:1px solid #dfe2e7;padding-left:16px}nav{display:flex;padding:4px;gap:2px;margin:auto;background:#f1f2f4;border-radius:9px}nav button{border:0;background:none;font:inherit;font-size:13px;color:#676e78;padding:7px 18px;border-radius:6px;cursor:pointer}nav button[aria-pressed=true]{background:#fff;color:#22272e;box-shadow:0 1px 4px #172a4122}header>a{font-size:12px;color:#727986;text-decoration:none}main{max-width:1512px;margin:24px auto;padding:0 28px}.scene{border:1px solid #c7cdd7;border-radius:12px;overflow:hidden;box-shadow:0 18px 60px #34476a1f}.scene[hidden]{display:none}.scene>svg{display:block;width:100%;height:auto}.scene g[role=button][tabindex]{cursor:pointer}.scene g[role=button][tabindex]:hover>rect:first-of-type{filter:brightness(.97)}.scene g[role=button]:focus-visible,.scene g[role=slider]:focus-visible{outline:2px solid #087ff5;outline-offset:4px}.scene g[aria-disabled=true]{cursor:not-allowed}.scene g[role=slider]{cursor:ew-resize;touch-action:none}footer{display:flex;align-items:center;justify-content:space-between;gap:24px;min-height:52px;color:#68727f;font-size:12px}footer a{color:#68727f;text-decoration:none}button:focus-visible,a:focus-visible{outline:2px solid #087ff5;outline-offset:3px}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
</style></head><body><header><div class="brand"><svg viewBox="0 0 28 28" aria-hidden="true"><rect width="28" height="28" rx="8" fill="#087ff5"/><path d="M8 12V8h4M16 8h4v4M20 16v4h-4M12 20H8v-4" fill="none" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg>ccShot<span class="draft">界面试稿 · 示例内容</span></div><nav aria-label="设计画面">'''+''.join(nav)+'''</nav><a href="../UI参考与设计.md">参考说明 ↗</a></header><main>'''+''.join(boards)+'''<footer><span id="hint" role="status" aria-live="polite"></span><a href="../界面草案.html">查看第一版草案 ↗</a></footer></main><script>'''+SCRIPT+'</script></body></html>'
    (ROOT/'设计稿.html').write_text(html,encoding='utf-8')
    print('已生成 7 个 SVG 设计画板与离线网页试稿。')
    import sys
    if '--png' in sys.argv:
        export_png()


def export_png():
    """用 macOS Quick Look 导出矢量稿；不是浏览器截图或 App 运行截图。"""
    import subprocess
    from tempfile import TemporaryDirectory
    from PIL import Image
    with TemporaryDirectory(prefix='ccshot-ui-render-') as scratch:
        temporary=Path(scratch)
        for name,_,_ in SCENES:
            source=ROOT/f'{name}.svg'
            square=temporary/source.name
            # Quick Look 使用正方形缩略图，补空白后裁掉，避免宽画板被截断。
            square.write_text(source.read_text().replace('height="900" viewBox="0 0 1440 900"','height="1440" viewBox="0 0 1440 1440"'),encoding='utf-8')
            subprocess.run(['qlmanage','-t','-s','1440','-o',scratch,str(square)],stdout=subprocess.DEVNULL,check=True)
            with Image.open(temporary/(source.name+'.png')) as image:
                assert image.size==(1440,1440),image.size
                image.crop((0,0,1440,900)).save(ROOT/f'{name}.png')
    print('已导出 7 张 1440×900 PNG 设计画板。')


if __name__=='__main__':
    main()
