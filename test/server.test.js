import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { readFileSync } from "node:fs";
import { createApp } from "../server.js";
const configuredProjects = JSON.parse(
  readFileSync(new URL("../projects.json", import.meta.url), "utf8"),
);
const valid = {
  project: configuredProjects[0].id,
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
        configuredProjects.map(({ id, name, url }) => ({
          id,
          name,
          url: url ? new URL(url).href : null,
        })),
      );
      const response = await post(base);
      assert.equal(response.status, 200);
      assert.equal((await response.json()).mode, "demo");
      for (const project of configuredProjects) {
        const projectResponse = await post(base, {
          ...valid,
          project: project.id,
        });
        assert.equal(projectResponse.status, 200);
      }
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
test("SNS SDK uses standard AWS environment settings to sign and publish", async (t) => {
  let request;
  const endpoint = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    request = {
      authorization: req.headers.authorization,
      body: new URLSearchParams(Buffer.concat(chunks).toString()),
    };
    res.writeHead(200, { "Content-Type": "text/xml", Connection: "close" });
    res.end(
      '<PublishResponse xmlns="http://sns.amazonaws.com/doc/2010-03-31/"><PublishResult><MessageId>test-message</MessageId></PublishResult><ResponseMetadata><RequestId>test-request</RequestId></ResponseMetadata></PublishResponse>',
    );
  });
  await new Promise((resolve) => endpoint.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => endpoint.close(resolve)));
  const settings = {
    AWS_REGION: "eu-west-2",
    AWS_ACCESS_KEY_ID: "test-access-key",
    AWS_SECRET_ACCESS_KEY: "test-secret-key",
    AWS_SESSION_TOKEN: "test-session-token",
    AWS_ENDPOINT_URL_SNS: `http://127.0.0.1:${endpoint.address().port}`,
    AWS_IGNORE_CONFIGURED_ENDPOINT_URLS: "false",
    REGION: undefined,
    AWS_DEFAULT_REGION: undefined,
  };
  for (const [key, value] of Object.entries(settings)) {
    const previous = process.env[key];
    t.after(() => {
      if (previous === undefined) delete process.env[key];
      else process.env[key] = previous;
    });
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  const topic = "arn:aws:sns:eu-west-2:123456789012:test-feedback";
  await withApp({ mode: "sns", topic }, async (base) => {
    const response = await post(base);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).mode, "sns");
    assert.match(request.authorization, /Credential=test-access-key\//);
    assert.match(request.authorization, /\/eu-west-2\/sns\/aws4_request/);
    assert.equal(request.body.get("Action"), "Publish");
    assert.equal(request.body.get("TopicArn"), topic);
    assert.equal(JSON.parse(request.body.get("Message")).likes, "Easy to use");
  });
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
