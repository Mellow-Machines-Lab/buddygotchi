#!/usr/bin/env python3
"""WCAG 2.x contrast for Boop's Warm Terminal palette (values from app/Boop/Views/Theme.swift)."""
P = dict(
 paper=("#FAF7F2","#1B1815"), raised=("#F3EDE3","#24211C"), well=("#EBE3D6","#2C2822"),
 hairline=("#E4DACA","#38332B"), hairlineStrong=("#D6C8B2","#4A4339"),
 ink=("#24211C","#F2EBE0"), inkSoft=("#675F53","#ADA396"), inkFaint=("#A29888","#787064"),
 amber=("#FFB000","#FFB000"), amberInk=("#82540F","#E8B970"), sage=("#6E9B5E","#6E9B5E"),
 sageInk=("#466638","#A3CC90"), clayInk=("#9C3B2E","#F09384"), blush=("#F1787D","#F1787D"),
 recording=("#FF3B30","#FF3B30"), fill=("#000000","#E8DCC4"), fillPressed=("#2A2620","#CFC2A8"),
 fillLabel=("#E8DCC4","#000000"), white=("#FFFFFF","#FFFFFF"), terminal=("#24211C","#24211C"),
 oat=("#E8DCC4","#E8DCC4"), glass=("#000000","#000000"),
 lane0=("#3AD2CE",)*2, lane1=("#FF8ADE",)*2, lane2=("#B58EFF",)*2, lane3=("#9CE763",)*2,
 inkSoftDark=("#ADA396",)*2, inkDark=("#F2EBE0",)*2, clayInkDark=("#F09384",)*2, amberInkDark=("#E8B970",)*2, sageInkDark=("#A3CC90",)*2,
 confettiBlue=("#3A9BF0",)*2,
)
def rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
def hx(c): return "#%02X%02X%02X" % tuple(round(x*255) for x in c)
def mix(fg, a, bg): return tuple(a*f+(1-a)*b for f,b in zip(fg,bg))
def lum(c):
    f=lambda v: v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    return 0.2126*f(c[0])+0.7152*f(c[1])+0.0722*f(c[2])
def cr(a,b):
    x,y=lum(a),lum(b); return (max(x,y)+0.05)/(min(x,y)+0.05)
def C(name, mode):
    """name, or ('mix', fg, alpha, bg) nested"""
    if isinstance(name, tuple): _, f, a, b = name; return mix(C(f,mode), a, C(b,mode))
    return rgb(P[name][mode])
def nm(x): return x if isinstance(x,str) else f"{nm(x[1])}@{x[2]:g} over {nm(x[3])}"
amberCard=('mix','amber',0.08,'raised'); nowCard=('mix','ink',0.08,'raised')
chip=lambda t,bg='raised': ('mix',t,0.12,bg)
nightL=('mix_raw',); 
P['nightL']=("#3B3328","#05070D")
wellNight=('mix','nightL',0.2,'well')  # light: 0.2; dark handled below
rows=[]  # (group, what, fg, bg, need, where)
def add(g, what, fg, bg, need, where): rows.append((g,what,fg,bg,need,where))
T="text"; 
for bg in ['paper','raised','well']:
    for fg in ['ink','inkSoft','inkFaint','amberInk','sageInk','clayInk']:
        add('1 inks on surfaces', f'{fg} on {bg}', fg, bg, 4.5, 'Theme.swift:56-64')
for fg in ['ink','inkSoft','amberInk']:
    add('2 needs-you card', f'{fg} on amber card', fg, amberCard, 4.5, 'OverviewPane.swift:399-420')
add('2 needs-you card','amber stroke (0.45) vs paper',('mix','amber',0.45,'raised'),'paper',3,'Theme.swift:170')
for fg in ['ink','inkSoft','amberInk','sageInk','clayInk']:
    add('3 status chip', f'{fg} on its chip (12% over raised)', fg, chip(fg), 4.5, 'Theme.swift:409-419')
add('3 status chip','inkSoft on header chip (well)','inkSoft','well',4.5,'OverviewPane.swift:203-207')
# inkFaint used as text
add('4 inkFaint as text','"Feeling" / "· Level n" 11pt on paper','inkFaint','paper',4.5,'OverviewPane.swift:174,177')
add('4 inkFaint as text','"TRY" 10pt on paper','inkFaint','paper',4.5,'Onboarding/OnboardingBoard.swift:334')
add('4 inkFaint as text','disabled quiet button label on paper','inkFaint','paper',4.5,'Theme.swift:431')
add('4 inkFaint as text','"you" 9pt, out of the world, on well','inkFaint','well',4.5,'WorldBand.swift:154-156')
add('4 inkFaint as text','moon icon 14pt on raised (graphic)','inkFaint','raised',3,'OverviewPane.swift:439')
# session bars
for l in ['lane0','lane1','lane2','lane3']:
    add('5 lane bars (3pt, graphic)', f'{l} bar on raised', l, 'raised', 3, 'OverviewPane.swift:692,756')
add('5 lane bars (3pt, graphic)','amber bar (waiting) on raised','amber','raised',3,'OverviewPane.swift:691')
add('5 lane bars (3pt, graphic)','amber@0.4 bar (dismissed) on raised',('mix','amber',0.4,'raised'),'raised',3,'OverviewPane.swift:690')
add('5 lane bars (3pt, graphic)','inkSoft bar (working, no lane) on raised','inkSoft','raised',3,'OverviewPane.swift:692')
add('5 lane bars (3pt, graphic)','hairlineStrong bar (idle) on raised','hairlineStrong','raised',3,'OverviewPane.swift:693')
# ring
add('6 ring','blush arc on paper','blush','paper',3,'BoopPane.swift:116')
add('6 ring','sage arc (full) on paper','sage','paper',3,'BoopPane.swift:116')
add('6 ring','well track on paper','well','paper',3,'BoopPane.swift:113')
add('6 ring','blush arc vs well track','blush','well',3,'BoopPane.swift:113-116')
add('6 ring','sage arc vs well track','sage','well',3,'BoopPane.swift:113-116')
add('6 ring','ink number in ring on paper','ink','paper',4.5,'BoopPane.swift:33')
add('6 ring','inkSoft "today" 11pt on paper','inkSoft','paper',4.5,'BoopPane.swift:34')
# dots
for t,w in [('amber','needs you'),('inkSoft','working'),('inkFaint','idle/asleep/stopped'),('recording','listening')]:
    add('7 dots (6-7pt, graphic)', f'StateDot {t} ({w}) on paper', t, 'paper', 3, 'OverviewPane.swift:311-318')
for t,w in [('sage','connected'),('inkFaint','not connected'),('clayInk','trouble')]:
    add('7 dots (6-7pt, graphic)', f'device dot {t} ({w}) on paper', t, 'paper', 3, 'OverviewPane.swift:223,241')
add('7 dots (6-7pt, graphic)','amber StateDot on raised (onboarding tip)','amber','raised',3,'Onboarding/OnboardingFinish.swift:410')
# controls
add('8 controls','switch on: sage track vs raised','sage','raised',3,'Theme.swift:517')
add('8 controls','switch off: hairlineStrong track vs raised','hairlineStrong','raised',3,'Theme.swift:517')
add('8 controls','switch knob: white on sage','white','sage',3,'Theme.swift:520')
add('8 controls','switch knob: white on hairlineStrong (off)','white','hairlineStrong',3,'Theme.swift:520')
add('8 controls','slider groove hairlineStrong vs raised','hairlineStrong','raised',3,'Theme.swift:551')
add('8 controls','slider fill ink vs raised','ink','raised',3,'Theme.swift:552')
add('8 controls','slider knob white vs raised','white','raised',3,'Theme.swift:553')
add('8 controls','slider knob white vs ink fill','white','ink',3,'Theme.swift:553')
add('8 controls','filled button label on fill','fillLabel','fill',4.5,'Theme.swift:469-472')
add('8 controls','filled button label on pressed fill','fillLabel','fillPressed',4.5,'Theme.swift:472')
add('8 controls','filled button vs raised card','fill','raised',3,'Theme.swift:495')
add('8 controls','filled button vs paper','fill','paper',3,'Theme.swift:472')
add('8 controls','disabled filled button (0.4) label on its fill, over paper',('mix','fillLabel',0.4,'paper'),('mix','fill',0.4,'paper'),4.5,'Theme.swift:474')
add('8 controls','outlined row button: ink on paper','ink','paper',4.5,'Theme.swift:492-495')
add('8 controls','outlined row button: hairlineStrong edge vs raised','hairlineStrong','raised',3,'Theme.swift:497')
add('8 controls','outlined row button: paper fill vs raised','paper','raised',3,'Theme.swift:495')
add('8 controls','disabled row button (0.4): ink on paper, over raised',('mix','ink',0.4,'raised'),('mix','paper',0.4,'raised'),4.5,'Theme.swift:498')
add('8 controls','field edge hairlineStrong vs raised','hairlineStrong','raised',3,'Theme.swift:307')
add('8 controls','field focus edge inkSoft vs raised','inkSoft','raised',3,'Theme.swift:307')
add('8 controls','quiet button hover: ink on well','ink','well',4.5,'Theme.swift:431-434')
add('8 controls','quiet button pressed: ink on hairline','ink','hairline',4.5,'Theme.swift:434')
add('8 controls','tab, not chosen: inkSoft on well','inkSoft','well',4.5,'OverviewPane.swift:811')
add('8 controls','tab chosen pill: paper vs well','paper','well',3,'OverviewPane.swift:816')
add('8 controls','row picker chosen pill: paper vs well','paper','well',3,'SettingsPane.swift:439')
add('8 controls','card edge: hairline vs paper','hairline','paper',3,'Theme.swift:170')
add('8 controls','card fill: raised vs paper','raised','paper',3,'Theme.swift:168')
# onboarding
add('9 onboarding','step tick: paper on sage','paper','sage',3,'Onboarding/OnboardingView.swift:156-158')
add('9 onboarding','step number, now: paper on ink','paper','ink',4.5,'Onboarding/OnboardingView.swift:160')
add('9 onboarding','step number, later: ink on hairline','ink','hairline',4.5,'Onboarding/OnboardingView.swift:160')
add('9 onboarding','"waiting…" inkSoft on the now card (ink 8% over raised)','inkSoft',nowCard,4.5,'Onboarding/OnboardingView.swift:174')
add('9 onboarding','speech bubble: paper on ink','paper','ink',4.5,'Onboarding/OnboardingView.swift:195-197')
add('9 onboarding','plug bolt: paper on inkSoft','paper','inkSoft',3,'Onboarding/OnboardingBoard.swift:222-223')
add('9 onboarding','footprints not walked: hairlineStrong on paper','hairlineStrong','paper',3,'Onboarding/OnboardingView.swift:78')
add('9 onboarding','"zzz" 18pt heavy inkSoft on paper','inkSoft','paper',3,'Onboarding/OnboardingBoard.swift:217')
add('9 onboarding','sample-words capsule edge hairlineStrong on paper','hairlineStrong','paper',3,'Onboarding/OnboardingBoard.swift:350')
for fg in ['oat','inkSoftDark','clayInkDark','amberInkDark','sageInkDark','inkDark']:
    add('9 onboarding',f'terminal: {fg} on terminal card',fg,'terminal',4.5,'Onboarding/OnboardingIntro.swift:83-88; OnboardingFinish.swift:166-173')
add('9 onboarding','terminal card vs paper','terminal','paper',3,'Onboarding/OnboardingView.swift:267')
add('9 onboarding','checkmark.circle.fill sage on raised','sage','raised',3,'Onboarding/OnboardingFinish.swift:347')
add('9 onboarding','amber 5pt ring around the face on paper','amber','paper',3,'Onboarding/OnboardingIntro.swift:150')
# face
add('10 face tile','tile edge hairlineStrong@0.6 on paper',('mix','hairlineStrong',0.6,'paper'),'paper',3,'BoopFace.swift:81')
add('10 face tile','needs-you edge amber on paper','amber','paper',3,'BoopFace.swift:81')
add('10 face tile','needs-you edge amber vs glass','amber','glass',3,'BoopFace.swift:79-81')
# world band
for t,w in [('lane0','coding'),('lane2','testing'),('amber','shipping'),('blush','waiting'),('sage','resting')]:
    add('11 world band (5-6pt dots)', f'{t} dot ({w}) on well, day side', t, 'well', 3, 'WorldBand.swift:140-148')
add('11 world band (5-6pt dots)','"you" 9pt semibold ink on well','ink','well',4.5,'WorldBand.swift:156')
add('11 world band (5-6pt dots)','region names 9pt inkSoft on paper','inkSoft','paper',4.5,'WorldBand.swift:164')
add('11 world band (5-6pt dots)','pick ring ink on well','ink','well',3,'WorldBand.swift:43')
add('11 world band (5-6pt dots)','own ring ink@0.6 on well',('mix','ink',0.6,'well'),'well',3,'WorldBand.swift:38')
add('11 world band (5-6pt dots)','you line ink@0.35 on well',('mix','ink',0.35,'well'),'well',3,'WorldBand.swift:155')
import sys
def run():
    out=[]; cur=None; fails=[]
    for g,what,fg,bg,need,where in rows:
        if g!=cur:
            cur=g; out.append(f"\n**{g}**\n\n| pair | light | dark | needs | where |\n| --- | --- | --- | --- | --- |")
        cells=[]
        for m in (0,1):
            f,b=C(fg,m),C(bg,m); r=cr(f,b); ok=r>=need
            cells.append(f"{hx(f)} on {hx(b)} = **{r:.2f}**{'' if ok else ' FAIL'}")
            if not ok: fails.append((what,'light' if m==0 else 'dark',r,need,where))
        out.append(f"| {what} | {cells[0]} | {cells[1]} | {need}:1 | {where} |")
    # night side of the band: per mode alpha
    out.append("\n**12 world band, night side** (light: #3B3328 at 0.2 over the well; dark: #05070D at 0.8)\n\n| pair | light | dark | needs |\n| --- | --- | --- | --- |")
    nights=(mix(rgb("#3B3328"),0.2,C('well',0)), mix(rgb("#05070D"),0.8,C('well',1)))
    asleep=(mix(C('inkFaint',0),0.7,None) if False else None)
    for t,w in [('lane0','coding'),('lane2','testing'),('amber','shipping'),('blush','waiting'),('sage','resting'),('ink','"you" text')]:
        cells=[]
        for m in (0,1):
            r=cr(C(t,m),nights[m]); need=4.5 if t=='ink' else 3
            cells.append(f"{hx(C(t,m))} on {hx(nights[m])} = **{r:.2f}**{'' if r>=need else ' FAIL'}")
            if r<need: fails.append((f'{t} ({w}) on the band, night side','light' if m==0 else 'dark',r,need,'WorldBand.swift:118'))
        out.append(f"| {t} ({w}) | {cells[0]} | {cells[1]} | {'4.5' if t=='ink' else '3'}:1 |")
    # asleep dots
    for label,bgs in [('day side',(C('well',0),C('well',1))),('night side',nights)]:
        l=mix(C('inkFaint',0),0.7,bgs[0]); d=mix(C('inkSoft',1),0.55,bgs[1])
        rl,rd=cr(l,bgs[0]),cr(d,bgs[1])
        out.append(f"| asleep dot, {label} | {hx(l)} on {hx(bgs[0])} = **{rl:.2f}**{'' if rl>=3 else ' FAIL'} | {hx(d)} on {hx(bgs[1])} = **{rd:.2f}**{'' if rd>=3 else ' FAIL'} | 3:1 |")
        if rl<3: fails.append((f'asleep dot, {label}','light',rl,3,'WorldBand.swift:135'))
        if rd<3: fails.append((f'asleep dot, {label}','dark',rd,3,'WorldBand.swift:135'))
    out.append("\n**13 menu bar**\n\n| pair | ratio | needs |\n| --- | --- | --- |")
    for what,f,b in [("menuAmberLight on a light bar (#F5F5F5)","#B87400","#F5F5F5"),("amber on a dark bar (#2A2A2A)","#FFB000","#2A2A2A"),("amber on a light bar (not used)","#FFB000","#F5F5F5")]:
        out.append(f"| {what} | **{cr(rgb(f),rgb(b)):.2f}** | 3:1 |")
    out.append(f"\n**Failures: {len(fails)} of {2*len(rows)+16} pair-modes**\n\n| pair | mode | ratio | needs | where |\n| --- | --- | --- | --- | --- |")
    for what,m,r,need,where in fails: out.append(f"| {what} | {m} | {r:.2f} | {need} | {where} |")
    return "\n".join(out)
if __name__=="__main__": print(run())
