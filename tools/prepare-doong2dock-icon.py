"""Optimize the already-created Doong2Dock launcher mascot for website display."""
from pathlib import Path
from PIL import Image
import sys

source = Path(sys.argv[1])
target = Path(__file__).resolve().parents[1] / "public" / "doong2dock-icon.webp"
with Image.open(source) as image:
    image = image.convert("RGBA")
    image.thumbnail((440, 440), Image.Resampling.LANCZOS)
    image.save(target, format="WEBP", quality=85, method=6)
print("doong2dock site icon prepared", target, target.stat().st_size)
