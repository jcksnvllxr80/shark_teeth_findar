"""Convert the RF100 shark-teeth COCO dataset to YOLO format, single class."""
import json
import shutil
from pathlib import Path

SRC = Path("rf100/home/zuppif/Documents/Work/RoboFlow/ODinW-RF100-challenge/rf100/shark-teeth-5atku")
DST = Path("shark_yolo")

splits = {"train": "train", "valid": "val", "test": "test"}

for src_split, dst_split in splits.items():
    coco = json.loads((SRC / src_split / "_annotations.coco.json").read_text())
    images = {img["id"]: img for img in coco["images"]}
    anns_by_image: dict[int, list] = {}
    for ann in coco["annotations"]:
        anns_by_image.setdefault(ann["image_id"], []).append(ann)

    img_dir = DST / "images" / dst_split
    lbl_dir = DST / "labels" / dst_split
    img_dir.mkdir(parents=True, exist_ok=True)
    lbl_dir.mkdir(parents=True, exist_ok=True)

    n_boxes = 0
    for img_id, img in images.items():
        src_img = SRC / src_split / img["file_name"]
        shutil.copy2(src_img, img_dir / img["file_name"])
        w, h = img["width"], img["height"]
        lines = []
        for ann in anns_by_image.get(img_id, []):
            x, y, bw, bh = ann["bbox"]
            cx = (x + bw / 2) / w
            cy = (y + bh / 2) / h
            lines.append(f"0 {cx:.6f} {cy:.6f} {bw / w:.6f} {bh / h:.6f}")
            n_boxes += 1
        (lbl_dir / (Path(img["file_name"]).stem + ".txt")).write_text("\n".join(lines))
    print(f"{dst_split}: {len(images)} images, {n_boxes} boxes")

(DST / "data.yaml").write_text(
    f"path: {DST.resolve()}\n"
    "train: images/train\n"
    "val: images/val\n"
    "test: images/test\n"
    "names:\n  0: shark tooth\n"
)
print("wrote", DST / "data.yaml")
