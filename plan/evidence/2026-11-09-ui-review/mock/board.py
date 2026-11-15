from PIL import Image, ImageDraw, ImageFont
G='/tmp/boop-sim/v1-polish-d3b1e3/gel/'; T='/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish/internal/tools/fontgen/geist-mono/GeistMono-SemiBold.ttf'
sign=ImageFont.truetype(T,28); large=ImageFont.truetype(T,22)
def ctext(d,cx,y,s,f,fill):
    w=d.textlength(s,font=f); d.text((cx-w/2,y),s,font=f,fill=fill)
def pair(a,b,out,label):
    W=a.width*2+16; im=Image.new('RGB',(W,a.height+20),(60,60,60)); im.paste(a,(0,20)); im.paste(b,(a.width+16,20)); d=ImageDraw.Draw(im)
    d.text((4,4),'before: '+label,fill=(255,255,0)); d.text((a.width+20,4),'after (mockup)',fill=(255,255,0)); im.save(out)
# 1 needs you with its kind
before=Image.open(G+'states/needs_you.png').convert('RGB')
base=Image.open(G+'states/working.png').convert('RGB'); after=base.copy()
after.paste(before.crop((0,328,502,410)),(0,328)); d=ImageDraw.Draw(after)
d.rounded_rectangle((91,16,411,92),20,fill=(255,176,0))
d.ellipse((111,36,147,72),outline=(28,20,0),width=3); ctext(d,129,37,'?',sign,(28,20,0))
d.text((163,20),'NEEDS YOU',font=sign,fill=(28,20,0)); d.text((163,54),'a yes or no',font=sign,fill=(70,50,0))
pair(before,after,'board-needs-you.png','states/needs_you.png')
# 2 ring + level, one moment
before=Image.open(G+'v1/ring-closed.png').convert('RGB'); after=before.copy(); d=ImageDraw.Draw(after)
d.rectangle((0,380,502,410),fill=(0,0,0)); d.rectangle((368,10,502,44),fill=(0,0,0)); d.text((378,12),'100',font=large,fill=(246,244,238))
x0,x1=120,382; d.rounded_rectangle((x0,277,x1,325),12,fill=(27,55,78),outline=(120,164,200),width=2)
for cx in (x0,x1): d.ellipse((cx-12,289,cx+12,313),fill=(74,175,255),outline=(27,55,78))
ctext(d,251,283,"today's done!",sign,(184,233,245))
gold=(242,196,86); x0,x1=126,376; d.rounded_rectangle((x0,346,x1,392),14,fill=(22,20,18),outline=gold,width=2)
for cx in (x0,x1): d.ellipse((cx-10,359,cx+10,379),fill=(74,175,255))
ctext(d,251,351,'* level 13!',sign,gold)
pair(before,after,'board-ring-level.png','v1/ring-closed.png')
# 3 the strip in words
before=Image.open(G+'lane/working-counts.png').convert('RGB'); after=before.copy(); d=ImageDraw.Draw(after)
d.rectangle((0,354,502,410),fill=(0,0,0)); x=61
for s,c in (('2',(246,244,238)),(' working · ',(173,163,150)),('3',(246,244,238)),(' idle',(173,163,150))):
    d.text((x,362),s,font=sign,fill=c); x+=d.textlength(s,font=sign)
pair(before,after,'board-strip.png','lane/working-counts.png')
# 4 narration readable
before=Image.open(G+'states/poked.png').convert('RGB'); after=before.copy(); d=ImageDraw.Draw(after)
d.rectangle((0,340,502,410),fill=(0,0,0)); d.line((55,348,446,348),fill=(58,54,50),width=2); d.rounded_rectangle((229,342,273,347),2,fill=(112,104,96))
ctext(d,251,364,'you poked Boop',large,(173,163,150))
pair(before,after,'board-narration.png','states/poked.png')
