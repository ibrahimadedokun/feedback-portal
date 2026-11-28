import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";

const projects = JSON.parse(readFileSync(new URL("../public/projects.json", import.meta.url), "utf8"));
const apiUrl = "https://feedback-api.example.test/v1";

test.beforeEach(async ({ page }) => {
  await page.route("**/config.js", (route) => route.fulfill({
    contentType: "text/javascript",
    body: `export const api = { baseUrl: "${apiUrl}/", healthPath: "/health", messagesPath: "/messages" };`,
  }));
  await page.route(`${apiUrl}/health`, (route) => route.fulfill({ status: 200, contentType: "text/plain", body: "Healthy" }));
  await page.route(`${apiUrl}/messages`, (route) => route.fulfill({ status: 204 }));
});

async function fillFeedback(page) {
  await page.getByRole("radio", { name: "4 stars — Really good", exact: true }).check();
  await page.getByLabel("What do you love about it?").fill("The features are easy to use.");
  await page.getByLabel("What could be even better?").fill("Add more filtering options.");
}

test("responsive feedback flow sends PublishMessageRequest and resets", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("combobox")).toHaveValue(projects[0].id);
  await expect(page.getByRole("option")).toHaveText(projects.map((project) => project.name));
  await page.getByRole("button", { name: "Send feedback" }).click();
  await expect(page.locator("#success-panel")).toBeHidden();
  await fillFeedback(page);
  await expect(page.locator("#rating-caption")).toHaveText("Really good");
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  const requestPromise = page.waitForRequest(`${apiUrl}/messages`);
  await page.getByRole("button", { name: "Send feedback" }).click();
  const request = await requestPromise;
  expect(request.method()).toBe("POST");
  expect(request.headers()["content-type"]).toBe("application/json");
  expect(request.postDataJSON()).toEqual({
    subject: `New ${projects[0].name} feedback`,
    message: `Project: ${projects[0].name} (${projects[0].id})\nRating: 4/5\n\nWhat do you love about it?\nThe features are easy to use.\n\nWhat could be even better?\nAdd more filtering options.`,
  });
  await expect(page.getByText("That’s how better begins.")).toBeVisible();
  await expect(page.locator("#success-message")).toContainText("Your feedback has been sent.");
  await page.getByRole("button", { name: "Share more thoughts" }).click();
  await expect(page.getByLabel("What do you love about it?")).toHaveValue("");
  await expect(page.locator("#rating-caption")).toHaveText("Your honest take");
});

test("health check starts in parallel and does not block loading or submission", async ({ page }) => {
  let completeHealth;
  const pendingHealth = new Promise((resolve) => { completeHealth = resolve; });
  await page.route(`${apiUrl}/health`, async (route) => {
    await pendingHealth;
    await route.fulfill({ status: 200, body: "Healthy" });
  });
  const healthRequest = page.waitForRequest(`${apiUrl}/health`);
  await page.goto("/");
  await healthRequest;
  try {
    await expect(page.locator("#feedback-form")).toBeVisible();
    await fillFeedback(page);
    await page.getByRole("button", { name: "Send feedback" }).click();
    await expect(page.locator("#success-panel")).toBeVisible();
  } finally {
    completeHealth();
  }
});

for (const failure of ["server", "network"]) {
  test(`${failure} health check failure stays silent and allows submission`, async ({ page }) => {
    await page.route(`${apiUrl}/health`, (route) => failure === "network"
      ? route.abort("failed")
      : route.fulfill({ status: 503 }));
    await page.goto("/");
    await expect(page.locator("#api-status")).toHaveCount(0);
    await expect(page.getByText("The feedback service may be unavailable.", { exact: false })).toHaveCount(0);
    await expect(page.locator("#feedback-form")).toBeVisible();
    await fillFeedback(page);
    await page.getByRole("button", { name: "Send feedback" }).click();
    await expect(page.locator("#success-panel")).toBeVisible();
  });
}

for (const failure of ["json", "text", "network"]) {
  test(`${failure} delivery failure retains feedback and allows retry`, async ({ page }) => {
    await page.route(`${apiUrl}/messages`, (route) => failure === "network" ? route.abort("failed") : route.fulfill({
      status: 502,
      contentType: failure === "json" ? "application/json" : "text/plain",
      body: failure === "json" ? JSON.stringify({ detail: "Delivery failed. Please try again." }) : "Bad gateway",
    }));
    await page.goto("/");
    await fillFeedback(page);
    await page.getByRole("button", { name: "Send feedback" }).click();
    await expect(page.getByRole("alert")).toBeVisible();
    await expect(page.getByLabel("What do you love about it?")).toHaveValue("The features are easy to use.");
    await expect(page.getByRole("button", { name: "Send feedback" })).toBeEnabled();
    await page.route(`${apiUrl}/messages`, (route) => route.fulfill({ status: 202, body: "Accepted" }));
    await page.getByRole("button", { name: "Send feedback" }).click();
    await expect(page.locator("#success-panel")).toBeVisible();
  });
}
