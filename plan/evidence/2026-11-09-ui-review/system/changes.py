#!/usr/bin/env python3
"""Every literal that leaves the proposed scale: file:line, old -> new. Rules in findings.md section 7."""
import re, glob, os
ROOT="/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish"
files=sorted(glob.glob(ROOT+"/app/Boop/Views/*.swift")+glob.glob(ROOT+"/app/Boop/Views/Onboarding/*.swift")+glob.glob(ROOT+"/app/Boop/Views/Slime/*.swift"))
rel=lambda f: os.path.relpath(f,ROOT+"/app/Boop/Views")
SP={'1':'2','3':'4','5':'4','7':'8','9':'8','10':'8 (Theme.gapSnug) or 12 (Theme.gap) for a card\'s padding','11':'12','13':'12','14':'16 in onboarding, 12 in the popover','18':'16','22':'24','30':'32','6':'8 beside an icon (HStack), 4 between lines (VStack)'}
TOK={'Theme.gapSnug + 2':'Theme.gapSnug (8); the icon column goes 18 -> 20','Theme.gutter - 8':'Theme.gapSnug (8): gutter 16 less the quiet button\'s 8','Theme.gutter - 4':'Theme.gap (12)','Theme.gapLoose':'Theme.gutter (16): one name for one value','Theme.gutter':'16 (was 18)'}
FS={'8':'10','9':'10','10.5':'11','12.5':'12','13':'12 in the popover, 14 (lead) in onboarding','15':'14 (lead)'}
FB={'14':'15','16':'15 (or 18 for the pane title)','17':'18','20':'18','26':'28','30':'28'}
RAD={'7':'Theme.wellRadius (8)','10':'Theme.wellRadius (8)','6':'Theme.chipRadius (same value, use the token)','3':'2','12':'Theme.cardRadius (same value, use the token)'}
out={k:[] for k in ['spacing','padding','token arithmetic','font size (system)','font size (rounded)','font weight','radius','icon column','opacity/shadow']}
for f in files:
    for i,l in enumerate(open(f),1):
        if l.strip().startswith('//'): continue
        w=f"{rel(f)}:{i}"
        for m in re.finditer(r"spacing:\s*([\d.]+)\b",l):
            v=m.group(1)
            if v in SP:
                new=SP[v]
                if v=='6': new='8' if 'HStack' in l else '4' if 'VStack' in l else new
                if v=='10': new='8'
                if v=='14': new='16' if 'Onboarding' in f else '12'
                out['spacing'].append((w,f"spacing: {v}",new))
        for m in re.finditer(r"\.padding\(((?:\.[a-zA-Z]+|\[[^\]]*\])?,?\s*)(-?[\d.]+)\)",l):
            v=m.group(2)
            if v in SP:
                new=SP[v]
                if v=='6': new='8' if '.vertical' in m.group(1) or '.top' in m.group(1) or m.group(1)=='' else '8'
                if v=='10': new='12' if m.group(1).strip()=='' else '12' if 'horizontal' in m.group(1) else '8'
                if v=='14': new='16' if 'Onboarding' in f else '12'
                out['padding'].append((w,f".padding({m.group(1)}{v})",new))
        for m in re.finditer(r"Card\(padding:\s*(10|14)",l):
            out['padding'].append((w,f"Card(padding: {m.group(1)})", 'Card() (12)' if m.group(1)=='10' else 'Card(padding: 16), the one roomy card'))
        for k,new in TOK.items():
            if k in l and not (k=='Theme.gutter' and ('Theme.gutter -' in l or 'static let' in l)) and 'static let' not in l:
                if k in('Theme.gutter',): continue
                out['token arithmetic'].append((w,k,new))
        for m in re.finditer(r"\.system\(size:\s*([\d.]+)",l):
            v=m.group(1)
            if v in FS:
                new=FS[v]
                if v=='13': new='14 (lead)' if 'Onboarding' in f else '12'
                if v=='12.5' and 'monospaced' in l: new='12, monospaced'
                if v=='10.5': new='11, monospaced'
                out['font size (system)'].append((w,f"system {v}",new))
        for m in re.finditer(r"\.boop\((\d+)",l):
            if m.group(1) in FB: out['font size (rounded)'].append((w,f"boop {m.group(1)}",FB[m.group(1)]))
        if re.search(r"\.boop\(compact \? 14 : 15",l): out['font size (rounded)'].append((w,"boop compact ? 14 : 15","15"))
        if '.heavy' in l: out['font weight'].append((w,"heavy","bold"))
        m=re.search(r"\.system\(size: [\d.]+, weight: \.bold\)",l)
        if m: out['font weight'].append((w,m.group(0),"weight: .semibold (bold stays with the rounded face)"))
        for m in re.finditer(r"cornerRadius:\s*(\d+)\)",l):
            if m.group(1) in RAD: out['radius'].append((w,f"cornerRadius: {m.group(1)}",RAD[m.group(1)]))
        for m in re.finditer(r"radius:\s*(7|12)\b(?!,\s*y)",l):
            if 'shadow' not in l: out['radius'].append((w,f"radius: {m.group(1)}",RAD[m.group(1)]))
        if re.search(r"\.frame\(width: (16|18)\)",l): out['icon column'].append((w,re.search(r"\.frame\(width: \d+\)",l).group(0),".frame(width: 20)"))
        if '.shadow(' in l: out['opacity/shadow'].append((w,re.search(r"\.shadow\([^)]*\)[^)]*\)",l).group(0) if re.search(r"\.shadow\([^)]*\)[^)]*\)",l) else '.shadow',"one of two: Theme.shadowKnob (black 0.2, radius 1, y 0.5) or Theme.shadowLift (black 0.16, radius 14, y 8)"))
        if re.search(r"enabled \? 1 : 0\.4|found \? 1 : 0\.6",l): out['opacity/shadow'].append((w,re.search(r"(enabled|found) \? 1 : 0\.\d",l).group(0),"Theme.disabled (0.4)"))
n=0
for k,v in out.items():
    print(f"\n**{k}** ({len(v)})\n\n| where | old | new |\n| --- | --- | --- |")
    for w,o,nw in v: print(f"| {w} | `{o}` | {nw} |"); n+=1
print(f"\nTotal: {n} places.")
