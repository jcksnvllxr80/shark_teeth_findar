#!/bin/bash
# One command to retrain the shark tooth detector and install it into the app.
#
#   ./training/retrain.sh                    # retrain on the RF100 dataset (auto-downloads)
#   ./training/retrain.sh path/to/data.yaml  # retrain on your own labeled dataset (YOLO format)
#
# Tunables via environment variables:
#   EPOCHS=80   number of training epochs
#   IMGSZ=640   training image size
#   BASE=training/best.pt   weights to start from
#
# When it finishes, SharkToothAR/SharkToothDetector.mlpackage is replaced and the
# Xcode project regenerated — just build and run in Xcode to use the new model.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAIN_DIR="$ROOT/training"
WORK="$TRAIN_DIR/work"
VENV="$TRAIN_DIR/venv"
EPOCHS="${EPOCHS:-80}"
IMGSZ="${IMGSZ:-640}"
BASE="${BASE:-$TRAIN_DIR/best.pt}"

mkdir -p "$WORK"

# 1. Python environment (created once, reused on later runs)
if [ ! -x "$VENV/bin/yolo" ]; then
    echo "==> Creating Python environment (one-time, downloads ~2 GB, takes a few minutes)"
    PY="$(command -v python3.12 || command -v python3.13 || command -v python3.11 || command -v python3)"
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet ultralytics coremltools
fi

# 2. Dataset
if [ $# -ge 1 ]; then
    DATA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    echo "==> Using dataset: $DATA"
else
    DATA="$WORK/shark_yolo/data.yaml"
    if [ ! -f "$DATA" ]; then
        echo "==> Downloading RF100 shark-teeth dataset"
        curl -sL -o "$WORK/dataset.tar.gz" \
            "https://huggingface.co/datasets/Francesco/shark-teeth-5atku/resolve/main/dataset.tar.gz"
        mkdir -p "$WORK/rf100"
        # tar prints harmless hardlink warnings for this archive; ignore them
        tar -xzf "$WORK/dataset.tar.gz" -C "$WORK/rf100" 2>/dev/null || true
        (cd "$WORK" && "$VENV/bin/python" "$TRAIN_DIR/coco_to_yolo.py")
    fi
fi

# 3. Train
echo "==> Training for $EPOCHS epochs (starting from $BASE)"
"$VENV/bin/yolo" detect train model="$BASE" data="$DATA" \
    epochs="$EPOCHS" imgsz="$IMGSZ" device=mps patience=20 \
    project="$WORK/runs" name=shark exist_ok=True

BEST="$WORK/runs/shark/weights/best.pt"
if [ ! -f "$BEST" ]; then
    # ultralytics sometimes nests the save dir; find the newest best.pt
    BEST="$(find "$WORK/runs" -name best.pt -print0 | xargs -0 ls -t | head -1)"
fi
echo "==> Best weights: $BEST"

# 4. Export to Core ML and install into the app
"$VENV/bin/python" "$TRAIN_DIR/export_coreml.py" "$BEST"
rm -rf "$ROOT/SharkToothAR/SharkToothDetector.mlpackage"
cp -R "${BEST%.pt}.mlpackage" "$ROOT/SharkToothAR/SharkToothDetector.mlpackage"
echo "==> Installed SharkToothAR/SharkToothDetector.mlpackage"

# 5. Keep the new weights as the base for future runs (previous ones backed up)
if [ -f "$TRAIN_DIR/best.pt" ]; then
    cp "$TRAIN_DIR/best.pt" "$TRAIN_DIR/best.prev.pt"
fi
cp "$BEST" "$TRAIN_DIR/best.pt"

# 6. Regenerate the Xcode project so the new model is picked up
if command -v xcodegen >/dev/null; then
    (cd "$ROOT" && xcodegen generate)
fi

echo ""
echo "Done. Open SharkToothAR.xcodeproj and press Cmd-R to run with the new model."
