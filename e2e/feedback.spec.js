import { test, expect } from "@playwright/test";
test("responsive feedback flow with validation, rating, and reset", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByRole("combobox")).toHaveValue("footielineup");
  await expect(page.getByRole("option")).toHaveCount(2);
  await expect(page.getByRole("option")).toHaveText([
    "FootieLineup",
    "Islamic Wordle",
  ]);
  await expect(page.getByText("Demo mode ·")).toBeVisible();
  await page.getByRole("button", { name: "Send feedback" }).click();
  await expect(page.locator("#success-panel")).toBeHidden();
  await page
    .getByRole("radio", { name: "4 stars — Really good", exact: true })
    .check();
  await expect(page.locator("#rating-caption")).toHaveText("Really good");
  await page
    .getByLabel("What do you love about it?")
    .fill("Creating my matchday lineup.");
  await page
    .getByLabel("What could be even better?")
    .fill("Add more formations.");
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: `test-results/feedback-${test.info().project.name}.png`,
    fullPage: true,
  });
  await page.getByRole("button", { name: "Send feedback" }).click();
  await expect(page.getByText("That’s how better begins.")).toBeVisible();
  await expect(page.locator("#success-message")).toContainText(
    "not stored or delivered",
  );
  await page.getByRole("button", { name: "Share more thoughts" }).click();
  await expect(page.getByLabel("What do you love about it?")).toHaveValue("");
  await expect(page.locator("#rating-caption")).toHaveText("Your honest take");
});
test("delivery failure retains feedback and allows retry", async ({ page }) => {
  await page.goto("/");
  await page
    .getByRole("radio", { name: "5 stars — Love it!", exact: true })
    .check();
  await page.getByLabel("What do you love about it?").fill("The design");
  await page.getByLabel("What could be even better?").fill("More teams");
  await page.route("**/api/feedback", (route) =>
    route.fulfill({
      status: 502,
      contentType: "application/json",
      body: JSON.stringify({ error: "Delivery failed. Please try again." }),
    }),
  );
  await page.getByRole("button", { name: "Send feedback" }).click();
  await expect(page.getByRole("alert")).toContainText("Delivery failed");
  await expect(page.getByLabel("What do you love about it?")).toHaveValue(
    "The design",
  );
  await expect(
    page.getByRole("button", { name: "Send feedback" }),
  ).toBeEnabled();
});
