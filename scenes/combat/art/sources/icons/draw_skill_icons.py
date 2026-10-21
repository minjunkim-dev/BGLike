"""Draw the temporary 64px skill icons with Pillow. Shapes are placed by hand; no generator is used."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUTLINE = (26, 18, 28, 255)
STEEL = ((236, 240, 244), (176, 186, 200), (104, 112, 134))
WOOD = ((184, 122, 68), (130, 80, 42), (82, 48, 30))
GOLD = ((255, 228, 124), (236, 176, 48), (168, 102, 26))
INDIGO = ((118, 118, 204), (66, 62, 146), (38, 34, 92))
TEAL = ((126, 220, 204), (46, 152, 142), (24, 92, 90))
GREEN = ((156, 226, 112), (78, 170, 64), (40, 104, 44))
RED = ((246, 112, 96), (202, 46, 46), (124, 24, 36))
CYAN = ((214, 250, 255), (96, 202, 242), (40, 120, 192))
SKIN = ((252, 216, 172), (222, 166, 120), (160, 104, 76))
STONE = ((200, 180, 142), (150, 128, 98), (98, 82, 66))
WHITE = (250, 248, 236)


def attack(d):
    d.line([(19, 45), (50, 14)], STEEL[1], 9)
    d.line([(17, 43), (48, 12)], STEEL[0], 3)
    d.line([(23, 47), (52, 18)], STEEL[2], 2)
    d.polygon([(46, 9), (58, 6), (55, 18)], STEEL[1])
    d.line([(49, 10), (57, 7)], STEEL[0], 2)
    d.line([(11, 37), (27, 53)], GOLD[1], 6)
    d.line([(11, 37), (19, 45)], GOLD[0], 2)
    d.line([(17, 47), (8, 56)], WOOD[1], 6)
    d.ellipse((3, 52, 11, 60), GOLD[1])
    d.point([(5, 54), (6, 54), (5, 55)], GOLD[0])


def second_wind(d):
    for y, length, color in ((18, 22, WHITE), (31, 14, CYAN[0])):
        d.line([(4, y - 1), (4 + length, y - 1)], color, 4)
        d.arc((length - 6, y - 15, length + 12, y + 1), 180, 450, color, 4)
    d.rectangle((35, 26, 47, 60), GREEN[1])
    d.rectangle((25, 37, 57, 49), GREEN[1])
    d.rectangle((35, 26, 38, 60), GREEN[0])
    d.rectangle((25, 37, 57, 39), GREEN[0])
    d.rectangle((45, 41, 47, 60), GREEN[2])
    d.rectangle((40, 47, 57, 49), GREEN[2])


def surge(d):
    bolt = [(40, 3), (12, 36), (29, 36), (20, 61), (52, 24), (34, 24), (46, 3)]
    d.polygon(bolt, GOLD[1])
    d.line([(40, 4), (14, 35)], GOLD[0], 3)
    d.line([(29, 37), (22, 56)], GOLD[0], 2)
    d.line([(51, 25), (24, 56)], GOLD[2], 2)


def parry(d):
    d.ellipse((4, 14, 44, 58), STEEL[2])
    d.ellipse((8, 18, 40, 54), INDIGO[1])
    d.pieslice((8, 18, 40, 54), 180, 270, INDIGO[0])
    d.ellipse((19, 30, 29, 42), STEEL[1])
    d.point([(21, 32), (22, 32), (21, 33)], STEEL[0])
    d.arc((22, 2, 62, 42), 230, 350, WHITE, 4)
    d.polygon([(54, 12), (62, 22), (52, 26)], WHITE)
    d.line([(46, 32), (58, 40)], CYAN[0], 3)
    d.line([(44, 40), (52, 50)], CYAN[0], 3)


def opportunity(d):
    blade = Image.new("L", (64, 64))
    shape = ImageDraw.Draw(blade)
    shape.ellipse((2, 4, 46, 60), 255)
    shape.ellipse((12, 2, 54, 52), 0)
    d.bitmap((0, 0), blade, STEEL[0])
    d.arc((2, 4, 46, 60), 110, 200, STEEL[1], 3)
    d.rectangle((47, 6, 57, 38), RED[1])
    d.rectangle((47, 6, 49, 38), RED[0])
    d.rectangle((47, 45, 57, 55), RED[1])
    d.rectangle((47, 45, 49, 47), RED[0])


def mark(d):
    d.ellipse((7, 7, 57, 57), outline=RED[1], width=6)
    d.arc((7, 7, 57, 57), 180, 270, RED[0], 3)
    d.ellipse((22, 22, 42, 42), outline=RED[1], width=4)
    for line in ([(32, 2), (32, 18)], [(32, 46), (32, 62)], [(2, 32), (18, 32)], [(46, 32), (62, 32)]):
        d.line(line, RED[2], 5)
    d.rectangle((30, 30, 34, 34), RED[0])


def shock(d):
    d.line([(10, 54), (44, 20)], WOOD[1], 4)
    d.line([(10, 53), (43, 20)], WOOD[0], 1)
    d.polygon([(59, 5), (40, 14), (50, 24)], STEEL[1])
    d.line([(58, 6), (42, 14)], STEEL[0], 2)
    d.polygon([(6, 46), (16, 44), (14, 52)], TEAL[1])
    d.polygon([(18, 58), (20, 48), (12, 50)], TEAL[2])
    for zigzag in ([(30, 4), (38, 10), (32, 14), (40, 20)], [(60, 26), (52, 32), (58, 36), (50, 44)],
                   [(24, 24), (28, 32), (20, 32)]):
        d.line(zigzag, CYAN[1], 4, joint="curve")
        d.line(zigzag, CYAN[0], 1)


def disengage(d):
    d.arc((26, 2, 62, 62), 270, 450, WOOD[1], 5)
    d.arc((26, 2, 62, 62), 300, 340, WOOD[0], 2)
    d.line([(44, 4), (44, 60)], WHITE, 1)
    d.polygon([(2, 32), (18, 18), (18, 26), (40, 26), (40, 38), (18, 38), (18, 46)], TEAL[1])
    d.polygon([(4, 31), (17, 20), (17, 27), (39, 27), (39, 29), (16, 29)], TEAL[0])
    d.rectangle((18, 36, 40, 38), TEAL[2])
    for y in (16, 48):
        d.line([(28, y), (40, y)], WHITE, 3)


def shove(d):
    d.rounded_rectangle((10, 24, 38, 54), 5, SKIN[1])
    for x in (10, 17, 24, 31):
        d.rounded_rectangle((x, 8 + abs(x - 21) // 2, x + 6, 30), 3, SKIN[1])
        d.line([(x + 1, 11 + abs(x - 21) // 2), (x + 1, 28)], SKIN[0], 2)
    d.polygon([(38, 34), (48, 24), (52, 28), (40, 46)], SKIN[1])
    d.line([(14, 50), (36, 50)], SKIN[2], 3)
    for start, end in (((44, 8), (56, 2)), ((46, 50), (60, 56)), ((52, 38), (62, 38))):
        d.line([start, end], WHITE, 3)


def jump(d):
    d.rectangle((4, 44, 26, 60), STONE[1])
    d.rectangle((4, 44, 26, 47), STONE[0])
    d.rectangle((38, 30, 60, 60), STONE[1])
    d.rectangle((38, 30, 60, 33), STONE[0])
    d.rectangle((38, 46, 60, 47), STONE[2])
    d.arc((12, 6, 52, 58), 190, 330, WHITE, 5)
    d.polygon([(42, 14), (56, 18), (46, 28)], WHITE)


def potion(d):
    d.rectangle((26, 10, 38, 28), STEEL[1])
    d.rectangle((23, 3, 41, 11), WOOD[1])
    d.rectangle((23, 3, 41, 5), WOOD[0])
    d.ellipse((10, 22, 54, 62), STEEL[1])
    d.ellipse((13, 25, 51, 59), RED[1])
    d.chord((13, 25, 51, 59), 200, 340, STEEL[0])
    d.pieslice((13, 25, 51, 59), 20, 160, RED[2])
    d.ellipse((18, 36, 24, 44), RED[0])


DRAWERS = {function.__name__: function for function in
           (attack, second_wind, surge, parry, opportunity, mark, shock, disengage, shove, jump, potion)}


def outlined(drawer):
    """Draw one icon and add the 2px dark contour that survives the 0.5 display scale."""
    image = Image.new("RGBA", (64, 64))
    drawer(ImageDraw.Draw(image))
    alpha = image.getchannel("A").point(lambda value: 255 if value else 0)
    ring = ImageChops.subtract(alpha.filter(ImageFilter.MaxFilter(5)), alpha)
    result = Image.new("RGBA", (64, 64))
    result.paste(OUTLINE, mask=ring)
    result.alpha_composite(image)
    return result


parser = argparse.ArgumentParser()
parser.add_argument("destination", type=Path)
args = parser.parse_args()
record = json.loads((Path(__file__).parent / "skill_icon_generation.json").read_text())
assert [icon["id"] for icon in record["icons"]] == list(DRAWERS)
args.destination.mkdir(parents=True, exist_ok=True)
for action, drawer in DRAWERS.items():
    icon = outlined(drawer)
    assert icon.size == (64, 64) and icon.getbbox()
    icon.save(args.destination / f"{action}.png")
print(json.dumps({"icons": len(DRAWERS), "canvas": [64, 64], "display_scale": 0.5}))
