import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../server.js";
const valid = {
  project: "footielineup",
  rating: 5,
  likes: " Easy to use ",
  improvements: " More formations ",
};
async function withApp(config, run) {
  const server = createApp(config);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}
const post = (base, body = valid, extra = {}) =>
  fetch(base + "/api/feedback", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...extra },
    body: JSON.stringify(body),
  });
test("demo submission does not publish; project config and static app load", async () => {
  await withApp(
    { mode: "demo", publish: () => assert.fail("must not publish") },
    async (base) => {
      assert.equal((await fetch(base)).status, 200);
      const config = await (await fetch(base + "/api/config")).json();
      assert.deepEqual(
        config.projects.map(({ id, name, url }) => ({ id, name, url })),
        [
          {
            id: "footielineup",
            name: "FootieLineup",
            url: "https://footielineup.example.com/",
          },
          { id: "islamicwordle", name: "Islamic Wordle", url: null },
        ],
      );
      const response = await post(base);
      assert.equal(response.status, 200);
      assert.equal((await response.json()).mode, "demo");
      const secondProjectResponse = await post(base, {
        ...valid,
        project: "islamicwordle",
      });
      assert.equal(secondProjectResponse.status, 200);
    },
  );
});
test("SNS submission publishes a validated, trimmed payload before success", async () => {
  let message;
  await withApp(
    {
      mode: "sns",
      topic: "mock-topic",
      region: "eu-west-2",
      publish: async (value) => {
        message = value;
      },
    },
    async (base) => {
      const response = await post(base);
      assert.equal(response.status, 200);
      assert.equal((await response.json()).mode, "sns");
      assert.equal(message.likes, "Easy to use");
      assert.equal(message.improvements, "More formations");
      assert.equal(message.rating, 5);
      assert.ok(message.id);
      assert.ok(message.submittedAt);
    },
  );
});
test("rejects invalid ratings, unknown projects, blank and oversized text", async () => {
  await withApp({ mode: "demo" }, async (base) => {
    for (const patch of [
      { rating: 0 },
      { rating: 6 },
      { rating: 2.5 },
      { rating: "5" },
      { project: "unknown" },
      { likes: " " },
      { improvements: "" },
      { likes: "x".repeat(2001) },
    ])
      assert.equal((await post(base, { ...valid, ...patch })).status, 400);
    assert.equal((await post(base, null)).status, 400);
    assert.equal(
      (await post(base, { ...valid, likes: "x".repeat(20000) })).status,
      413,
    );
    assert.equal(
      (
        await fetch(base + "/api/feedback", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{",
        })
      ).status,
      400,
    );
  });
});
test("missing configuration and publish failures never report success", async () => {
  await withApp({ mode: "sns", topic: "", region: "" }, async (base) =>
    assert.equal((await post(base)).status, 503),
  );
  await withApp(
    {
      mode: "sns",
      topic: "mock-topic",
      region: "eu-west-2",
      publish: async () => {
        throw new Error("unavailable");
      },
    },
    async (base) => assert.equal((await post(base)).status, 502),
  );
});
test("rejects cross-origin requests and limits repeated submissions", async () => {
  await withApp({ mode: "demo", rateLimit: 1 }, async (base) => {
    assert.equal(
      (await post(base, valid, { Origin: "https://other.example" })).status,
      403,
    );
    assert.equal((await post(base)).status, 200);
    assert.equal((await post(base)).status, 429);
  });
});
