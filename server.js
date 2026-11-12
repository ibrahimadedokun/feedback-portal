import http from "node:http";
import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const defaultProjects = JSON.parse(
  readFileSync(new URL("./projects.json", import.meta.url), "utf8"),
);

const publicDir = new URL("./public/", import.meta.url);
const assets = new Map([
  ["/", ["index.html", "text/html"]],
  ["/styles.css", ["styles.css", "text/css"]],
  ["/app.js", ["app.js", "text/javascript"]],
]);
const json = (res, status, data) => {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(JSON.stringify(data));
};
const safeUrl = (value) => {
  try {
    const url = new URL(value);
    return ["https:", "http:"].includes(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
};

export function createApp({
  mode = process.env.FEEDBACK_MODE || "sns",
  topic = process.env.SNS_TOPIC_ARN,
  region = process.env.AWS_REGION ||
    process.env.REGION ||
    process.env.AWS_DEFAULT_REGION,
  publish,
  rateLimit = 20,
} = {}) {
  const projects = defaultProjects.map((project) => ({
    ...project,
    url: safeUrl(project.url),
  }));
  const client =
    mode === "sns" && topic && region && !publish
      ? new SNSClient({ region, maxAttempts: 2 })
      : null;
  const send =
    publish ||
    ((message) =>
      client.send(
        new PublishCommand({
          TopicArn: topic,
          Subject: `New ${projects.find((project) => project.id === message.project)?.name || message.project} feedback`,
          Message: JSON.stringify(message),
        }),
        { abortSignal: AbortSignal.timeout(10000) },
      ));
  const attempts = new Map();
  return http.createServer(async (req, res) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    );
    try {
      const path = new URL(req.url, "http://localhost").pathname;
      if (req.method === "GET" && path === "/api/config")
        return json(res, 200, {
          projects,
          mode: mode === "demo" ? "demo" : "sns",
        });
      if (req.method === "POST" && path === "/api/feedback") {
        if (
          req.headers.origin &&
          req.headers.origin !== `http://${req.headers.host}` &&
          req.headers.origin !== `https://${req.headers.host}`
        )
          return json(res, 403, { error: "This request is not allowed." });
        if (!req.headers["content-type"]?.startsWith("application/json"))
          return json(res, 415, { error: "Send feedback as JSON." });
        const now = Date.now();
        for (const [key, value] of attempts)
          if (value.until <= now) attempts.delete(key);
        const ip = req.socket.remoteAddress;
        const record = attempts.get(ip) || { count: 0, until: now + 60000 };
        attempts.set(ip, record);
        if (++record.count > rateLimit) {
          res.setHeader("Retry-After", Math.ceil((record.until - now) / 1000));
          return json(res, 429, {
            error: "A few too many requests. Please try again in a minute.",
          });
        }
        const chunks = [];
        let size = 0;
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 16384) {
            json(res, 413, { error: "Your feedback is too long." });
            return;
          }
          chunks.push(chunk);
        }
        let body;
        try {
          body = JSON.parse(Buffer.concat(chunks).toString());
        } catch {
          return json(res, 400, { error: "Invalid JSON." });
        }
        if (
          !body ||
          typeof body !== "object" ||
          !projects.some((p) => p.id === body.project) ||
          !Number.isInteger(body.rating) ||
          body.rating < 1 ||
          body.rating > 5 ||
          typeof body.likes !== "string" ||
          typeof body.improvements !== "string" ||
          !body.likes.trim() ||
          !body.improvements.trim() ||
          body.likes.length > 2000 ||
          body.improvements.length > 2000
        )
          return json(res, 400, {
            error:
              "Choose a project, rate it from 1 to 5, and complete both feedback fields (up to 2,000 characters each).",
          });
        if (mode !== "demo" && (mode !== "sns" || !topic || !region))
          return json(res, 503, {
            error:
              "Feedback delivery is not configured yet. Please try again later.",
          });
        const message = {
          id: randomUUID(),
          project: body.project,
          rating: body.rating,
          likes: body.likes.trim(),
          improvements: body.improvements.trim(),
          submittedAt: new Date().toISOString(),
        };
        if (mode === "demo")
          return json(res, 200, { id: message.id, mode: "demo" });
        try {
          await send(message);
        } catch {
          console.error("SNS publish failed; feedback was not acknowledged.");
          return json(res, 502, {
            error:
              "We couldn’t deliver your feedback. Your text is still here; please try again.",
          });
        }
        return json(res, 200, { id: message.id, mode: "sns" });
      }
      if (req.method === "GET" && assets.has(path)) {
        const [file, type] = assets.get(path);
        res.writeHead(200, {
          "Content-Type": `${type}; charset=utf-8`,
          "Cache-Control": "no-cache",
        });
        res.end(await readFile(new URL(file, publicDir)));
        return;
      }
      json(res, 404, { error: "Not found" });
    } catch {
      if (!res.headersSent)
        json(res, 500, { error: "Something went wrong. Please try again." });
      else res.end();
    }
  });
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  createApp().listen(port, "0.0.0.0", () =>
    console.log(
      `Feedback portal listening on port ${port} (${process.env.FEEDBACK_MODE || "sns"} mode)`,
    ),
  );
}
