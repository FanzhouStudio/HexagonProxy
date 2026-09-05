from pathlib import Path
from PIL import Image
import sys


if len(sys.argv) >= 3:
    source_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
else:
    root = Path(__file__).resolve().parents[1]
    source_path = root / "assets" / "axolotl.png"
    output_dir = root / "assets"

output_dir.mkdir(parents=True, exist_ok=True)
source = Image.open(source_path).convert("RGBA")
alpha_box = source.getchannel("A").getbbox()
if alpha_box is not None:
    source = source.crop(alpha_box)

canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))

# Keep the icon fully transparent outside the mascot and enlarge the pixel art
# with an integer nearest-neighbour scale so its pixels stay crisp.
max_width, max_height = 232, 208
scale = max(1, min(max_width // source.width, max_height // source.height))
source = source.resize((source.width * scale, source.height * scale), Image.Resampling.NEAREST)
position = ((256 - source.width) // 2, (256 - source.height) // 2)
canvas.alpha_composite(source, position)

png_path = output_dir / "app_icon.png"
ico_path = output_dir / "app_icon.ico"
canvas.save(png_path)
canvas.save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print(png_path)
print(ico_path)
