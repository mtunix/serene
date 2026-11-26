import struct, sys, math
# A white disc on alpha, edge fading over FEATHER texels (anti-aliased at small sizes). Same circle for mask and ring.
# Options: --size=N (texels across) and --feather=N (texels the edge fades over), for a disc shown at another size:
# one screen pixel of feather is size / (pixels shown) texels. Without them: AuraDisc.
opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--'))
paths = [a for a in sys.argv[1:] if not a.startswith('--')]
W = H = int(opts.get('size', 128))
FEATHER = float(opts.get('feather', 4.0))  # texels the edge fades over (~1 screen pixel at 30 px)
R = W / 2 - FEATHER / 2 - 0.5               # radius in texels (a little margin to the edge)
out = bytearray()
for y in range(H):
    for x in range(W):
        d = math.hypot(x + 0.5 - W / 2, y + 0.5 - H / 2)
        a = (R - d) / FEATHER + 0.5
        a = max(0.0, min(1.0, a))
        a = a * a * (3 - 2 * a)  # smoothstep
        out += bytes((255, 255, 255, int(round(255 * a))))
# (an uncompressed 32-bit TGA, type 2: descriptor 40 is 8 alpha bits, rows from the top)
hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 40)
for path in paths:
    open(path, 'wb').write(hdr + out)
row = [out[(H // 2 * W + x) * 4 + 3] for x in range(0, 12)]
print('edge profile:', row)
