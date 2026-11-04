from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
source = root / ".build" / "AndroidTransfer-icon-1024.png"
sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
icon = Image.open(source).convert("RGBA")
for density, size in sizes.items():
    target = root / "mobile" / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png"
    icon.resize((size, size), Image.Resampling.LANCZOS).save(target)
