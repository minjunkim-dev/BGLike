"""Normalize generated terrain art with Pillow; no replacement art is drawn."""
import argparse
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
manifest = json.loads((args.source / "world_generation.json").read_text())
materials = {}
for item in manifest["materials"]:
    materials[item["id"]] = Image.open(args.source / item["source_path"]).convert("RGBA").resize(
        (64, 64), Image.Resampling.NEAREST)
atlas = Image.new("RGBA", (64 * 8, 32))
for kind, name in enumerate(["grass", "path", "stone", "water"]):
    texture = materials[name]
    for variant in range(2):
        for y in range(32):
            ny = (y + 0.5 - 16) / 16
            for x in range(64):
                nx = (x + 0.5 - 32) / 32
                if abs(nx) + abs(ny) > 1:
                    continue
                u = min(63, max(0, int((nx + ny + 1) * 32)))
                v = min(63, max(0, int((ny - nx + 1) * 32)))
                color = texture.getpixel(((u + variant * 16) % 64, (v + variant * 16) % 64))
                atlas.putpixel(((kind * 2 + variant) * 64 + x, y), (*color[:3], 255))
terrain = args.destination / "terrain"
terrain.mkdir(parents=True, exist_ok=True)
atlas.save(terrain / "floor_tiles.png")
materials["wall"].save(terrain / "wall.png")
props = args.destination / "props"
props.mkdir(parents=True, exist_ok=True)
for item in manifest["props"]:
    image = Image.open(args.source / item["source_path"]).convert("RGBA")
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("Empty prop: " + item["id"])
    image.putalpha(alpha)
    content = image.crop(bounds)
    width, height = [int(value) * 2 for value in item["frame_size"].split("x")]
    scale = min((width - 8) / content.width, (height - 16) / content.height)
    content = content.resize((max(1, round(content.width * scale)),
                              max(1, round(content.height * scale))), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (width, height))
    frame.alpha_composite(content, ((width - content.width) // 2, height - 8 - content.height))
    frame.save(props / (item["id"] + ".png"))
    assert frame.getbbox() and frame.getbbox()[3] <= height - 8
print(json.dumps({"atlas": [512, 32], "logical_tile": [32, 16], "props": len(manifest["props"]),
                  "resampling": "nearest", "alpha_threshold": 128}))
