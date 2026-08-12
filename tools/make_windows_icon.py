from pathlib import Path
from PIL import Image, ImageDraw
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
draw = ImageDraw.Draw(canvas)
draw.rounded_rectangle((8, 8, 248, 248), radius=46, fill=(8, 58, 78, 255), outline=(82, 211, 191, 255), width=8)

source.thumbnail((214, 174), Image.Resampling.NEAREST)
position = ((256 - source.width) // 2, (256 - source.height) // 2 + 8)
canvas.alpha_composite(source, position)

png_path = output_dir / "app_icon.png"
ico_path = output_dir / "app_icon.ico"
canvas.save(png_path)
canvas.save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print(png_path)
print(ico_path)
