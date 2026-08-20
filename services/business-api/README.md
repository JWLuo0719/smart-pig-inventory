# Business API

Spring Boot/MySQL is the business authority in route B+. It owns organization isolation, inventory state, evidence locks, audits and model job records. Long-running file transfer and inference must not run inside database transactions.

Run locally:

```powershell
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

The current baseline contains schema, security boundaries, health/capability endpoints and tested domain policies. Upload persistence controllers are intentionally not claimed complete until AC-01 through AC-12 are implemented.

