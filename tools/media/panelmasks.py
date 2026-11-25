import struct, sys, math, os
# The addons' panel's masks (Minimap.lua): its side facing the compass is an arc around the compass's middle.
# HoleMask: opaque, with a round hole in the middle (radius HOLE_R texels): the panel's glass outside a circle.
# DiscMask: a disc filling the texture (radius DISC_R): with the hole, a ring one pixel wide (the arc's hairline).
# Edges fade over FEATHER texels (about a screen pixel at the sizes they are drawn).
HOLE_W, HOLE_R = 512, 80.0
DISC_W, DISC_R = 256, 126.0
FEATHER = 1.0

def tga(path, width, alpha):
    out = bytearray()
    for y in range(width):
        for x in range(width):
            d = math.hypot(x + 0.5 - width / 2, y + 0.5 - width / 2)
            out += bytes((255, 255, 255, int(round(255 * max(0.0, min(1.0, alpha(d)))))))
    # (an uncompressed 32-bit TGA, type 2: descriptor 40 is 8 alpha bits, rows from the top)
    hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, width, width, 32, 40)
    open(path, 'wb').write(hdr + out)

media = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'Media')
tga(os.path.join(media, 'HoleMask.tga'), HOLE_W, lambda d: (d - HOLE_R) / FEATHER + 0.5)
tga(os.path.join(media, 'DiscMask.tga'), DISC_W, lambda d: (DISC_R - d) / FEATHER + 0.5)
print('HoleMask: hole', HOLE_R, 'of', HOLE_W, '; DiscMask: disc', DISC_R, 'of', DISC_W)
