export async function readLimitedRequestBody(request: Request, limit = 65536): Promise<Uint8Array> {
  if (Number(request.headers.get("content-length")) > limit) throw new RangeError("Request body limit");
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      const result = await reader.read(); if (result.done) break;
      length += result.value.byteLength;
      if (length > limit) { await reader.cancel(); throw new RangeError("Request body limit"); }
      chunks.push(result.value);
    }
  } finally { reader.releaseLock(); }
  const body = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
  return body;
}
