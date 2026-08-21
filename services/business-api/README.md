# Business API

Spring Boot/MySQL is the business authority in route B+. It owns organization isolation, inventory state, evidence locks, audits and model job records. Long-running file transfer and inference must not run inside database transactions.

Run locally:

```powershell
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

The service implements the P0 upload chain: create/recover package, idempotent complete Blob upload with SHA-256 verification, manifest validation, and transactional commit of the session, evidence references, inference job and outbox event. MinIO credentials are required through `MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY`; objects are staged before promotion to the private evidence namespace.

