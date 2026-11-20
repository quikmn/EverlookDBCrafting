# Builds the CurseForge/site screenshots (1920x1080) from UISandbox renders in raw/.
from PIL import Image, ImageDraw
import math
W,H=1920,1080
BG=Image.new("RGB",(W,H)); px=BG.load()
for y in range(H):
    for x in range(W):
        d=min(1,math.hypot((x-W/2)/W,(y-H*0.38)/H)*1.6)
        px[x,y]=tuple(int(a+(b-a)*d) for a,b in zip((0x13,0x22,0x3F),(0x07,0x0D,0x1A)))
def place(names,out,gap=70):
    ims=[Image.open(f"raw/{n}.png").convert("RGBA") for n in names]
    tw=sum(i.width for i in ims)+gap*(len(ims)-1); th=max(i.height for i in ims)
    s=min(1.0,1760/tw,980/th)
    ims=[i.resize((int(i.width*s),int(i.height*s)),Image.LANCZOS) for i in ims]
    g=int(gap*s); tw=sum(i.width for i in ims)+g*(len(ims)-1)
    c=BG.convert("RGBA"); x=(W-tw)//2
    for i in ims:
        y=(H-i.height)//2
        sh=Image.new("RGBA",c.size,(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle((x+10,y+14,x+i.width+10,y+i.height+14),14,fill=(0,0,0,120))
        c=Image.alpha_composite(c,sh); c.paste(i,(x,y),i); x+=i.width+g
    c.convert("RGB").save(out)
place(["planner-route"],"1-skill-up-planner.png")
place(["guide-steps","merchant-confirm"],"2-guide-and-buy-at-merchant.png",gap=120)
place(["craftlist"],"3-crafting-list.png")
place(["browser-reagent"],"4-recipe-browser.png")
place(["tooltip-material","tooltip-recipe"],"5-tooltips.png",gap=120)
place(["characters"],"6-your-characters.png")
