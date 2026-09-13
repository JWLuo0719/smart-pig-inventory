import { NextResponse } from "next/server";

import { isPermittedBackendRoute } from "@/lib/backend-route-policy";

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
  const permitted = isPermittedBackendRoute(request.method, route);
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
    headers: (() => {
      const outgoing = new Headers({
        "content-type": response.headers.get("content-type") ?? "application/json",
        "cache-control": "no-store",
      });
      const disposition = response.headers.get("content-disposition");
      if (disposition) outgoing.set("content-disposition", disposition);
      const length = response.headers.get("content-length");
      if (length) outgoing.set("content-length", length);
      return outgoing;
    })(),
  });
}

export const GET = proxy;
export const POST = proxy;
export const DELETE = proxy;
export const PUT = proxy;
