import struct, sys, math
# The hints' glow made round: Glow.tga is a soft ring around a rounded square (its line on the button's edge, soft
# in and out). This reads its profile from the middle outward (the mean of the four sides) and turns it about the
# middle, so GlowRound.tga is the same glow, same thickness and softness, as a circle at the same distance.
#   python3 tools/media/roundglow.py Media/Glow.tga Media/GlowRound.tga
src, out_path = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
W, H = struct.unpack('<HH', d[12:16])
top_left = d[17] & 0x20
px = d[18 + d[0]:]

def alpha(x, y):
    if not top_left:
        y = H - 1 - y
    return px[(y * W + x) * 4 + 3]

c = W // 2
half = W // 2
# (texel i out from the middle: right, left, down, up, averaged)
profile = []
for i in range(half):
    vals = [alpha(c + i, c), alpha(c - 1 - i, c), alpha(c, c + i), alpha(c, c - 1 - i)]
    profile.append(sum(vals) / 4.0)

def at(r):
    if r >= half - 1:
        return 0.0
    i = int(r)
    f = r - i
    return profile[i] * (1 - f) + profile[i + 1] * f

out = bytearray()
for y in range(H):
    for x in range(W):
        r = math.hypot(x + 0.5 - W / 2, y + 0.5 - H / 2) - 0.5
        out += bytes((255, 255, 255, int(round(max(0.0, min(255.0, at(max(0.0, r))))))))
hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
open(out_path, 'wb').write(hdr + out)
print('profile peak at texel', max(range(half), key=lambda i: profile[i]), 'of', half)
