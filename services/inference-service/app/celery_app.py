import os

from celery import Celery


broker_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
celery_app = Celery(
    "pig_inventory_inference",
    broker=broker_url,
    backend=broker_url,
    include=["app.tasks"],
)
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    task_track_started=True,
    task_time_limit=300,
    task_soft_time_limit=270,
)
