import json
from pathlib import Path
from PIL import Image

images_dir = Path("dataset/images")
out_path = Path("dataset/annotations.json")
rows = []
for p in sorted(images_dir.glob("*.jpg")):
    with Image.open(p) as im:
        w, h = im.size
    rows.append({
        "file_name": p.name,
        "width": w,
        "height": h,
        "boxes": []
    })

out_path.parent.mkdir(parents=True, exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"images": rows}, f, indent=2)
print("Wrote", out_path)
