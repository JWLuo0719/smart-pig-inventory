"""Generate a synthetic two-second MP4 for the isolated runtime test (OpenCV required)."""
from pathlib import Path
from uuid import uuid4
import cv2
import numpy as np

target = Path(__file__).resolve().parents[2] / "test-assets/generated/admin-runtime/video-evidence.mp4"
target.parent.mkdir(parents=True, exist_ok=True)
writer = cv2.VideoWriter(str(target), cv2.VideoWriter_fourcc(*"mp4v"), 10, (160, 120))
assert writer.isOpened(), "Synthetic MP4 encoder unavailable"
label = uuid4().hex[:8]
for _ in range(20):
    frame = np.zeros((120, 160, 3), dtype=np.uint8)
    cv2.putText(frame, label, (5, 65), cv2.FONT_HERSHEY_SIMPLEX, .5, (0, 255, 0), 1)
    writer.write(frame)
writer.release()
assert target.stat().st_size > 0
print("Generated synthetic two-second video fixture.")
