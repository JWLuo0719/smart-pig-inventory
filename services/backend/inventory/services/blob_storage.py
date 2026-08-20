from io import BytesIO
from pathlib import Path

from django.conf import settings


class BlobStore:
    """A small storage boundary so MinIO replaces local dev storage without API changes."""

    def put_bytes(self, key: str, body: bytes, content_type: str) -> None:
        if settings.OBJECT_STORAGE_BACKEND == "minio":
            self._minio().put_object(settings.MINIO_BUCKET, key, BytesIO(body), len(body), content_type=content_type)
            return
        target = Path(settings.MEDIA_ROOT) / key
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)

    def materialize(self, key: str, target: Path) -> Path:
        target.parent.mkdir(parents=True, exist_ok=True)
        if settings.OBJECT_STORAGE_BACKEND == "minio":
            response = self._minio().get_object(settings.MINIO_BUCKET, key)
            try:
                with target.open("wb") as output:
                    for chunk in response.stream(32 * 1024):
                        output.write(chunk)
            finally:
                response.close()
                response.release_conn()
            return target
        source = Path(settings.MEDIA_ROOT) / key
        target.write_bytes(source.read_bytes())
        return target

    @staticmethod
    def _minio():
        from minio import Minio

        client = Minio(
            settings.MINIO_ENDPOINT,
            access_key=settings.MINIO_ROOT_USER,
            secret_key=settings.MINIO_ROOT_PASSWORD,
            secure=False,
        )
        if not client.bucket_exists(settings.MINIO_BUCKET):
            client.make_bucket(settings.MINIO_BUCKET)
        return client


blob_store = BlobStore()

