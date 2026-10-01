#!/usr/bin/env python3
"""프로토타입용 도트 에셋 생성기. 이 폴더에서 실행하면 tiles.png와 units.png를 다시 만든다."""
import random
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).parent


def write_png(path: Path, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height, width = len(pixels), len(pixels[0])
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


# --- 타일: 32x16 아이소메트릭 마름모 4종 (풀 A, 풀 B, 꽃, 자갈) ---

TILE_W, TILE_H = 32, 16
CLEAR = (0, 0, 0, 0)


def tile(variant: int, rng: random.Random) -> list[list[tuple[int, int, int, int]]]:
    base = (78, 130, 64) if variant != 1 else (72, 122, 58)
    light, dark = (94, 150, 76), (64, 110, 52)
    edge_top, edge_bottom = (112, 168, 92), (46, 82, 38)
    rows = []
    for y in range(TILE_H):
        row = []
        for x in range(TILE_W):
            d = abs(x - 15.5) / 16 + abs(y - 7.5) / 8
            if d > 1.0:
                row.append(CLEAR)
                continue
            if d > 0.86:
                color = edge_top if y < 8 else edge_bottom
            else:
                r = rng.random()
                color = light if r < 0.12 else dark if r < 0.24 else base
            row.append(color + (255,))
        rows.append(row)
    decor = {2: [(232, 122, 160), (242, 222, 96), (240, 240, 240)], 3: [(150, 150, 150), (112, 112, 112), (135, 135, 135)]}
    for color in decor.get(variant, []):
        while True:
            x, y = rng.randrange(TILE_W), rng.randrange(TILE_H)
            if abs(x - 15.5) / 16 + abs(y - 7.5) / 8 < 0.6:
                rows[y][x] = color + (255,)
                break
    return rows


# --- 캐릭터: 16x24, 전사와 궁수. 팀별 색만 바꿔 2줄로 찍는다 ---

WARRIOR = [
    "................",
    "......oooo......",
    ".....ommmmo.....",
    "....ommmmmmo....",
    "....oMMMMMMo....",
    "....osssssso....",
    "....osesseso....",
    "....osssssso....",
    ".....osssso..om.",
    "....oottttoo.om.",
    "...ottttttttoom.",
    "..oottTttTttoom.",
    ".ommottttttosom.",
    ".ommottttttosom.",
    ".ommoTttttTo.om.",
    ".ommo.tttt.o.oo.",
    "..oo.opppppo....",
    ".....opp.ppo....",
    ".....opp.ppo....",
    ".....opp.ppo....",
    "....obbo.obbo...",
    "....obbo.obbo...",
    "....oooo.oooo...",
    "................",
]

ARCHER = [
    "................",
    "......oooo......",
    ".....oTTTTo.....",
    "....oTTTTTTo....",
    "....oTssssTo....",
    "....oTseseTo....",
    "....oTssssTo....",
    ".....oTTTTo...w.",
    "....oottttoo.ow.",
    "...ottttttttoow.",
    "..osttltttttosw.",
    "..os.tttlttto.w.",
    "..oo.ttttlttosw.",
    ".....otttttto.w.",
    ".....oppppppo.w.",
    ".....opp.ppo..w.",
    ".....opp.ppo.ow.",
    ".....opp.ppo....",
    "....obbo.obbo...",
    "....obbo.obbo...",
    "....oooo.oooo...",
    "................",
    "................",
    "................",
]

COMMON = {
    "o": (26, 22, 32), "s": (232, 190, 150), "e": (32, 30, 52),
    "m": (204, 208, 218), "M": (136, 140, 156), "p": (72, 62, 84),
    "b": (62, 42, 32), "w": (142, 92, 52), "l": (122, 82, 46),
}
TEAM = {
    "ally": {"t": (72, 132, 212), "T": (40, 86, 162)},
    "enemy": {"t": (204, 72, 62), "T": (142, 40, 42)},
}


def sprite(grid: list[str], team: str) -> list[list[tuple[int, int, int, int]]]:
    palette = COMMON | TEAM[team]
    assert len(grid) == 24 and all(len(row) == 16 for row in grid), "16x24이어야 함"
    for row in grid:
        for ch in row:
            assert ch == "." or ch in palette, f"팔레트에 없는 문자: {ch!r}"
    return [[CLEAR if ch == "." else palette[ch] + (255,) for ch in row] for row in grid]


def hstack(images):
    return [sum((img[y] for img in images), []) for y in range(len(images[0]))]


def main() -> None:
    rng = random.Random(7)
    write_png(HERE / "tiles.png", hstack([tile(v, rng) for v in range(4)]))
    ally = hstack([sprite(WARRIOR, "ally"), sprite(ARCHER, "ally")])
    enemy = hstack([sprite(WARRIOR, "enemy"), sprite(ARCHER, "enemy")])
    write_png(HERE / "units.png", ally + enemy)


if __name__ == "__main__":
    main()
