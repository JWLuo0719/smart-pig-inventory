import assert from "node:assert/strict";
import test from "node:test";
import { setImmediate } from "node:timers/promises";
import { ThumbnailQueue } from "./thumbnail-queue.ts";

function controlledLoader() {
  const started: Array<{ assetId: string; signal: AbortSignal; finish: () => void }> = [];
  let active = 0, maximum = 0;
  const load = (assetId: string, signal: AbortSignal) => {
    active++; maximum = Math.max(maximum, active);
    return new Promise<Blob>((resolve) => {
      started.push({ assetId, signal, finish: () => resolve(new Blob([assetId], { type: "image/jpeg" })) });
    }).finally(() => { active--; });
  };
  return { started, load, maximum: () => maximum };
}

test("a 50-image page issues only two requests at a time and drains every queued image", async () => {
  const loader = controlledLoader();
  const queue = new ThumbnailQueue(loader.load, () => true);
  const results = Promise.all(Array.from({ length: 50 }, (_, index) => queue.enqueue(`asset-${index}`)));
  for (let batch = 0; batch < 25; batch++) {
    assert.equal(loader.started.length, (batch + 1) * 2);
    loader.started[batch * 2].finish(); loader.started[batch * 2 + 1].finish();
    await setImmediate();
  }
  assert.equal((await results).length, 50);
  assert.equal(loader.maximum(), 2);
  queue.dispose();
});

test("cancelling one waiting component rejects it without starting its HTTP request", async () => {
  const loader = controlledLoader();
  const queue = new ThumbnailQueue(loader.load, () => true);
  const cancellation = new AbortController();
  const results = Promise.allSettled([
    queue.enqueue("first"), queue.enqueue("second"), queue.enqueue("cancelled", cancellation.signal), queue.enqueue("fourth"),
  ]);
  cancellation.abort();
  loader.started[0].finish();
  await setImmediate();
  assert.deepEqual(loader.started.map((job) => job.assetId), ["first", "second", "fourth"]);
  loader.started[1].finish(); loader.started[2].finish();
  const settled = await results;
  assert.equal(settled[2].status, "rejected");
  if (settled[2].status === "rejected") assert.equal(settled[2].reason.name, "AbortError");
  queue.dispose();
});

test("an identity switch rejects queued and late results before another HTTP request can start", async () => {
  const loader = controlledLoader();
  let identity = 1;
  const queue = new ThumbnailQueue(loader.load, () => identity === 1);
  const results = Promise.allSettled([queue.enqueue("first"), queue.enqueue("second"), queue.enqueue("waiting")]);
  identity = 2;
  loader.started[0].finish();
  await setImmediate();
  assert.equal(loader.started.length, 2);
  assert.equal(loader.started[1].signal.aborted, true);
  const settled = await results;
  assert.ok(settled.every((result) => result.status === "rejected"));
  loader.started[1].finish();
  await setImmediate();
});

test("disposing a query cancels all jobs while a new lifecycle can run despite old unresponsive fetches", async () => {
  const loader = controlledLoader();
  const oldQueue = new ThumbnailQueue(loader.load, () => true);
  const oldResults = Promise.allSettled([oldQueue.enqueue("old-1"), oldQueue.enqueue("old-2"), oldQueue.enqueue("old-waiting")]);
  oldQueue.dispose();
  assert.ok((await oldResults).every((result) => result.status === "rejected"));
  assert.equal(loader.started.length, 2);
  assert.ok(loader.started.every((job) => job.signal.aborted));
  const newQueue = new ThumbnailQueue(async () => new Blob(["new identity image"]), () => true);
  assert.equal(await (await newQueue.enqueue("new-image")).text(), "new identity image");
  await assert.rejects(oldQueue.enqueue("old-later"), { name: "AbortError" });
  newQueue.dispose();
  loader.started.forEach((job) => job.finish());
  await setImmediate();
});
