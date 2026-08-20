# Inference service

This service is an isolation boundary, not the business authority. The API enqueues versioned jobs; workers call a configured `CountingProvider`. The default provider returns `review_required` with no count.

No Ultralytics or research repository source is included in the default runtime. A future YOLOv13 adapter must be added as a separately reviewed provider with model checksum and regression evidence.

