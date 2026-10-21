"""Extract generated unit sheets. Requires Pillow; no new pixels are drawn."""
import argparse
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("unit_id", choices=["warrior", "archer", "spiderling", "mother_spider",
                                     "novice_barbarian", "novice_archer", "scrap_robot_1000",
                                     "scrap_robot_2000", "scrap_robot_3000"])
parser.add_argument("destination", type=Path)
args = parser.parse_args()
sheet = Image.open(args.source).convert("RGBA")
contents = []
for row in range(3):
    for column in range(4):
        slot = sheet.crop((round(column * sheet.width / 4), round(row * sheet.height / 3),
                          round((column + 1) * sheet.width / 4), round((row + 1) * sheet.height / 3)))
        alpha = slot.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
        slot.putalpha(alpha)
        bounds = alpha.getbbox()
        if bounds is None:
            raise ValueError(f"Empty frame {row}/{column}")
        contents.append(slot.crop(bounds))
width, height = (48, 30) if args.unit_id == "spiderling" else (60, 56)
scale = min(width / max(frame.width for frame in contents),
            height / max(frame.height for frame in contents))
for index, content in enumerate(contents):
    row, column = divmod(index, 4)
    state = ["idle", "move", "attack"][row]
    direction = "right" if column < 2 else "left"
    resized = content.resize((max(1, round(content.width * scale)), max(1, round(content.height * scale))),
                             Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (64, 64))
    frame.alpha_composite(resized, ((64 - resized.width) // 2, 56 - resized.height))
    path = args.destination / args.unit_id / state / direction / f"{column % 2:03}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.save(path)
    assert frame.getbbox() and frame.getbbox()[3] <= 56
print(json.dumps({"unit_id": args.unit_id, "source_size": sheet.size, "frames": 12,
                  "scale": scale, "canvas": [64, 64], "pivot": [32, 56]}))
