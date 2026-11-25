import struct, sys
# The copy icon (Media/IconCopy.tga): two sheets as rounded outlines, the back one cut where it passes behind
# the front one, sampled SS x SS times per texel for a smooth edge.
#   python3 tools/media/copyicon.py Media/IconCopy.tga
W=H=64; SS=4
def rr_dist(px,py,x0,y0,x1,y1,r):
    # signed distance to rounded rect
    cx=min(max(px,x0+r),x1-r); cy=min(max(py,y0+r),y1-r)
    dx=px-cx; dy=py-cy
    inside = x0<=px<=x1 and y0<=py<=y1
    d=(dx*dx+dy*dy)**0.5 - r
    return d
STROKE=5.0
front=(9,21,41,57,7)  # (x0, y0, x1, y1, corner radius)
back=(23,7,55,43,7)
GAP=4.0
def cover(px,py):
    # front outline
    d=rr_dist(px,py,*front)
    a = 1.0 if abs(d+STROKE/2)<=STROKE/2 else 0.0
    # back outline, cut where near/inside the front sheet
    db=rr_dist(px,py,*back)
    if abs(db+STROKE/2)<=STROKE/2 and d > GAP: a=1.0
    return a
out=bytearray()
for y in range(H):
    for x in range(W):
        s=0
        for sy in range(SS):
            for sx in range(SS):
                s+=cover(x+(sx+0.5)/SS, y+(sy+0.5)/SS)
        a=int(round(255*s/(SS*SS)))
        out+=bytes((255,255,255,a))
# (an uncompressed 32-bit TGA, type 2: descriptor 40 is 8 alpha bits, rows from the top)
hdr=struct.pack('<BBBHHBHHHHBB',0,0,2,0,0,0,0,0,W,H,32,40)
open(sys.argv[1],'wb').write(hdr+out)
# (a rough picture of it in the terminal)
rows=[]
for y in range(0,64,4):
    rows.append(''.join('#' if out[(y*64+x)*4+3]>128 else ('+' if out[(y*64+x)*4+3]>30 else ' ') for x in range(0,64,2)))
print('\n'.join(rows))
