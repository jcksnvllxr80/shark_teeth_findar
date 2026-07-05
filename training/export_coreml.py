"""Export trained YOLOv8 weights to a Vision-compatible Core ML package.

Usage: python export_coreml.py path/to/best.pt

nms=True wraps the model in a pipeline with non-maximum suppression, which is
what makes Vision return VNRecognizedObjectObservation with labels + boxes.
"""
import sys

from ultralytics import YOLO

weights = sys.argv[1] if len(sys.argv) > 1 else "best.pt"
model = YOLO(weights)
path = model.export(format="coreml", nms=True, imgsz=640)
print("exported:", path)
