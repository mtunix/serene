import struct, sys, math, os
# The calendar's button (Minimap.lua), larger than the other round buttons, white on alpha, tinted in the game:
#   CalendarRim: its rim, BadgeRim's ring at 128 texels, so at its larger size it is still as fine a line.
#   BadgeSky:  the sky in the badge's glass, inside its rim: strongest at the bottom (a horizon), gone above the
#              middle, so the date stays on dark glass.
#   IconSun:   a small sun, a disc with eight short rays.
#   IconMoon:  a crescent, its horns to the upper right.
# Each texel is sampled SS x SS times for a smooth edge. Written into Media/, or a folder given as the argument:
#   python3 tools/media/badgesky.py
SS = 4
folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'Media')


def write(name, size, alpha):
    out = bytearray()
    for y in range(size):
        for x in range(size):
            s = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    s += alpha(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
            out += bytes((255, 255, 255, int(round(255 * s / (SS * SS)))))
    # (an uncompressed 32-bit TGA, type 2: descriptor 40 is 8 alpha bits, rows from the top)
    hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 40)
    open(os.path.join(folder, name + '.tga'), 'wb').write(hdr + out)
    # (a rough picture of it in the terminal)
    step = size // 16
    for y in range(0, size, step):
        print(''.join(' .:-=+*#%@'[min(9, out[(y * size + x) * 4 + 3] * 10 // 256)] for x in range(0, size, step // 2 or 1)))
    print()


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# The sky: 64 texels like BadgeDisc, inside BadgeRim's ring (radius 30.5, the rim ~4 texels deep).
def sky(px, py):
    d = math.hypot(px - 32, py - 32)
    if d > 28.5:
        return 0.0
    edge = smooth((28.5 - d) / 1.5)
    rise = smooth((py - 26) / 34) # (0 above the middle, 1 at the bottom)
    return edge * rise ** 1.4


SUN_R, RAY_IN, RAY_OUT, RAY_W = 6.5, 10.0, 14.5, 1.4


def sun(px, py):
    x, y = px - 16, py - 16
    d = math.hypot(x, y)
    if d <= SUN_R:
        return 1.0
    if RAY_IN <= d <= RAY_OUT:
        a = math.atan2(y, x) % (math.pi / 4)
        off = min(a, math.pi / 4 - a) * d # (distance from the nearest ray's middle line)
        return 1.0 if off <= RAY_W else 0.0
    return 0.0


def moon(px, py):
    x, y = px - 16, py - 16
    if math.hypot(x, y) > 12.5:
        return 0.0
    return 1.0 if math.hypot(x - 5.5, y + 4.5) > 10.5 else 0.0


# The rim: BadgeRim's edges (outer at 60.8 of 64, ~3.9 texels deep), drawn on 128 texels.
RIM_OUT, RIM_DEEP = 60.8, 3.9


def rim(px, py):
    d = math.hypot(px - 64, py - 64)
    return 1.0 if RIM_OUT - RIM_DEEP <= d <= RIM_OUT else 0.0


write('CalendarRim', 128, rim)
write('BadgeSky', 64, sky)
write('IconSun', 32, sun)
write('IconMoon', 32, moon)
