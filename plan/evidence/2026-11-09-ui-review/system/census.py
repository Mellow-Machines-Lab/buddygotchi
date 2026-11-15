#!/usr/bin/env python3
"""Census of literal design values in the Mac views. Usage: census.py [section]"""
import re, sys, glob, collections, os
ROOT = "/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish"
files = sorted(glob.glob(ROOT+"/app/Boop/Views/*.swift") + glob.glob(ROOT+"/app/Boop/Views/Onboarding/*.swift")
               + glob.glob(ROOT+"/app/Boop/Views/Slime/*.swift") + [ROOT+"/app/Boop/MenuBarApp.swift"])
def rel(f): return os.path.relpath(f, ROOT+"/app/Boop").replace("Views/","")
lines = []
for f in files:
    for i, l in enumerate(open(f), 1):
        if l.strip().startswith("//"): continue
        lines.append((rel(f), i, l.rstrip("\n")))
def hist(name, pat, group=1, maxex=3, norm=None):
    h = collections.defaultdict(list)
    for f, i, l in lines:
        for m in re.finditer(pat, l):
            v = m.group(group) if group else m.group(0)
            if norm: v = norm(v)
            h[v].append(f"{f}:{i}")
    print(f"\n### {name}  (total {sum(len(v) for v in h.values())}, distinct {len(h)})\n")
    print("| value | count | examples |\n| --- | --- | --- |")
    def key(kv):
        try: return (0, float(kv[0]))
        except: return (1, kv[0])
    for v, ex in sorted(h.items(), key=key):
        print(f"| `{v}` | {len(ex)} | {', '.join(ex[:maxex])}{' …' if len(ex)>maxex else ''} |")
    return h
sec = sys.argv[1] if len(sys.argv) > 1 else "all"
if sec in ("all","pad"):
    hist("padding: all args", r"\.padding\(([^()]*(?:\([^()]*\))?[^()]*)\)", norm=lambda s: s.strip() or "(default)")
    hist("padding: numeric literal value only", r"\.padding\((?:\.[a-zA-Z]+|\[[^\]]*\])?,?\s*(-?[\d.]+)\)")
    hist("padding: Theme token", r"\.padding\((?:\.[a-zA-Z]+|\[[^\]]*\])?,?\s*(Theme\.[A-Za-z]+(?:\s*[-+*/]\s*[\d.]+)?)\)")
    hist("spacing:", r"spacing:\s*([^,)]+)")
if sec in ("all","font"):
    hist("font: full expression", r"\.font\((\.[^\n]*?\)|\.[a-zA-Z0-9]+)\)", maxex=2)
    hist("font size (system(size:) + boop())", r"(?:size:\s*|\.boop\()([\d.]+)")
    hist("font size, system only", r"\.system\(size:\s*([\d.]+)")
    hist("font size, .boop only", r"\.boop\(([\d.]+)")
    hist("font weight", r"weight:\s*\.([a-z]+)")
    hist("boop() explicit weight", r"\.boop\([\d.]+,\s*\.([a-z]+)\)")
    hist("design:", r"design:\s*\.([a-z]+)")
    hist("monospaced", r"(\.monospaced\(\)|\.monospacedDigit\(\)|design: \.monospaced|monospacedSystemFont|monospacedDigitSystemFont)")
    hist("semantic text styles", r"\.font\(\.(body|caption2?|callout|footnote|headline|subheadline|title[23]?|largeTitle)")
    hist("tracking/kerning", r"\.(?:tracking|kerning)\(([^)]+)\)")
    hist("lineSpacing", r"\.lineSpacing\(([^)]+)\)")
    hist("lineLimit", r"\.lineLimit\(([^)]+)\)")
    hist("NSFont", r"(NSFont\.[a-zA-Z]+\([^)]*\))")
if sec in ("all","radius"):
    hist("cornerRadius", r"cornerRadius:\s*([^,)]+(?:\)(?=\s*\*))?)")
    hist(".cornerRadius()", r"\.cornerRadius\(([^)]+)\)")
    hist("radius: (param)", r"[( ]radius:\s*([^,)]+)")
    hist("Capsule/Circle shapes", r"\b(Capsule|Circle|Ellipse)\(\)", maxex=2)
    hist("lineWidth", r"lineWidth:\s*([^,)]+(?:\)[^,)]*)?)")
    hist("shadow", r"\.shadow\(([^\n]*?)\)(?=\s|$|\.)")
if sec in ("all","frame"):
    hist("frame(width:height:) pairs", r"\.frame\((width:\s*[^,)]+,\s*height:\s*[^,)]+)\)")
    hist("frame(width:)", r"\.frame\((?:min|max|ideal)?[wW]idth:\s*([^,)]+)[,)]")
    hist("frame(height:)", r"\.frame\((?:[^)]*?,\s*)?(?:min|max|ideal)?[hH]eight:\s*([^,)]+)[,)]")
    hist("frame full", r"\.frame\(([^()]*(?:\([^()]*\))?[^()]*)\)", maxex=2)
if sec in ("all","opacity"):
    hist("opacity literal", r"\.?opacity\((?:[^()?]*\?\s*)?([\d.]+)(?:\s*:\s*[\d.]+)?\)")
    hist("opacity full", r"opacity\(([^()]*(?:\([^()]*\))?[^()]*)\)", maxex=2)
    hist("withAlphaComponent", r"withAlphaComponent\(([^)]+)\)")
if sec in ("all","color"):
    hist("Color(hex:) literal", r"(?:Color|NSColor)\(hex:\s*(\"[^\"]+\")\)")
    hist("hex strings anywhere", r"(\"#[0-9A-Fa-f]{6}\")")
    hist("Theme.<colour>", r"Theme\.(paper|raised|well|hairlineStrong|hairline|inkSoft|inkFaint|ink|amberInk|amber|sageInk|sage|clayInk|recording|glass|terminalEdge|terminal|fillPressed|fillLabel|fill|blush|lane|chipTint|cardTint)\b", maxex=2)
    hist("system colours", r"(?<![A-Za-z])(\.white|\.black|\.clear|\.primary|\.secondary|\.red|\.green|\.blue|\.orange|\.yellow|\.gray|\.accentColor|Color\.[a-z]+|NSColor\.[a-zA-Z]+)\b", maxex=3)
    hist("Color(red/white:)", r"(Color\((?:red|white|\.sRGB)[^\n]*?\))")
    hist("Theme spacing tokens", r"Theme\.(gutter|gapTight|gapSnug|gapLoose|gapSection|gap|windowGutter|cardRadius|wellRadius|chipRadius|width)\b", maxex=2)
if sec in ("all","a11y"):
    hist("a11y modifiers", r"\.(accessibility[A-Za-z]+|help|keyboardShortcut|focusable|focused|onExitCommand|onKeyPress|dynamicTypeSize|focusEffectDisabled|onMoveCommand|defaultFocus)\(", maxex=2)
    hist("button styles", r"\.buttonStyle\(([^\n]*?\)?)\)", maxex=2)
    hist("toggle styles", r"\.toggleStyle\(([^)]+)\)")
    hist("animation", r"\.(boopEase\([^)]*\)|boopSettle|boopPop|easeInOut\([^)]*\)|easeOut\([^)]*\)|easeIn\([^)]*\)|linear\([^)]*\)|spring\([^)]*\))", group=1, maxex=2)
