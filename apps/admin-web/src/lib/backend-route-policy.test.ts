import assert from "node:assert/strict";
import test from "node:test";

import { isPermittedBackendRoute } from "./backend-route-policy.ts";

test("permits every admin workflow route with its expected method", () => {
  const routes = [
    ["POST", "auth/login"],
    ["POST", "auth/refresh"],
    ["POST", "auth/logout"],
    ["GET", "me"],
    ["GET", "media-assets"],
    ["GET", "media-assets/abc/thumbnail"],
    ["DELETE", "media-assets/abc"],
    ["POST", "media-assets/abc/override-delete"],
    ["GET", "master-data/changes"],
    ["PUT", "master-data/organizations/00000000-0000-4000-8000-000000000001"],
    ["PUT", "master-data/buildings/00000000-0000-4000-8000-000000000001"],
    ["PUT", "master-data/pens/00000000-0000-4000-8000-000000000001"],
    ["GET", "inference-jobs/failed"],
    ["POST", "inference-jobs/abc/retries"],
    ["POST", "inventory-sessions/abc/confirm"],
    ["POST", "inventory-sessions/abc/corrections"],
    ["GET", "inventory-sessions/abc/versions"],
    ["GET", "inventory-reports/exports/pdf"],
  ] as const;

  for (const [method, route] of routes) {
    assert.equal(isPermittedBackendRoute(method, route), true, `${method} ${route}`);
  }
});

test("rejects wrong methods and route-shape bypasses", () => {
  const routes = [
    ["GET", "auth/login"],
    ["POST", "inventory-sessions/abc/versions"],
    ["GET", "inventory-sessions/abc/versions/extra"],
    ["DELETE", "media-assets"],
    ["DELETE", "media-assets/abc/content"],
    ["DELETE", "media-assets/abc/thumbnail"],
    ["POST", "media-assets/abc/thumbnail"],
    ["GET", "media-assets/abc/thumbnail/extra"],
    ["GET", "media-assets/abc/override-delete"],
    ["POST", "media-assets/abc"],
    ["POST", "master-data/buildings/00000000-0000-4000-8000-000000000001"],
    ["PUT", "master-data/users/00000000-0000-4000-8000-000000000001"],
    ["DELETE", "master-data/pens/00000000-0000-4000-8000-000000000001"],
    ["POST", "inference-jobs/failed"],
    ["GET", "inference-jobs/abc/retries"],
    ["DELETE", "inventory-sessions/abc"],
    ["GET", "media-assets/abc/content/extra"],
    ["GET", "../audit-events"],
  ] as const;

  for (const [method, route] of routes) {
    assert.equal(isPermittedBackendRoute(method, route), false, `${method} ${route}`);
  }
});
