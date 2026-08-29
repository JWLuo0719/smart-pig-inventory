import { NextResponse } from "next/server";

const upstream = process.env.BUSINESS_API_BASE_URL;

type RouteContext = { params: Promise<{ path: string[] }> };

async function proxy(request: Request, { params }: RouteContext) {
  if (!upstream) {
    return NextResponse.json(
      { code: "BUSINESS_API_NOT_CONFIGURED", message: "BUSINESS_API_BASE_URL is not configured." },
      { status: 503 },
    );
  }

  const { path } = await params;
  const route = path.join("/");
  const permitted = (request.method === "POST" && (
    route === "auth/login"
    || /^inventory-sessions\/[^/]+\/confirm$/.test(route)
    || /^review\/near-duplicates\/[^/]+\/resolve$/.test(route)
  )) || (request.method === "GET" && (
    route === "inventory-tasks"
    || route === "review/near-duplicates"
    || route === "inventory-reports/daily"
    || route === "inventory-reports/aggregate"
    || route === "audit-events"
    || /^inventory-sessions\/[^/]+$/.test(route)
    || /^inventory-sessions\/[^/]+\/media$/.test(route)
    || /^media-assets\/[^/]+\/content$/.test(route)
  ));
  if (!permitted) {
    return NextResponse.json({ code: "ROUTE_NOT_ALLOWED" }, { status: 404 });
  }
  const incoming = new URL(request.url);
  const target = new URL(`/api/v1/${path.map(encodeURIComponent).join("/")}`, upstream);
  target.search = incoming.search;
  const headers = new Headers();
  for (const name of ["authorization", "content-type", "x-idempotency-key", "x-correlation-id"]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  const response = await fetch(target, {
    method: request.method,
    headers,
    body: request.method === "GET" ? undefined : await request.arrayBuffer(),
    cache: "no-store",
  });
  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") ?? "application/json",
      "cache-control": "no-store",
    },
  });
}

export const GET = proxy;
export const POST = proxy;
export const DELETE = proxy;
export const PUT = proxy;
