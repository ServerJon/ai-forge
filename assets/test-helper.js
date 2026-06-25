/**
 * Helper utilities for web application testing with Playwright.
 * Designed for use with both the `webapp-testing` and `e2e-testing` skills.
 */

/**
 * Poll a condition function until it returns true or the timeout is reached.
 *
 * @param {() => Promise<boolean> | boolean} condition - Predicate to evaluate on each tick
 * @param {number} [timeout=5000] - Maximum wait time in milliseconds
 * @param {number} [interval=100] - Polling interval in milliseconds
 * @returns {Promise<true>} Resolves when condition is met
 * @throws {Error} If the condition is not met within the timeout
 */
async function waitForCondition(condition, timeout = 5000, interval = 100) {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    if (await condition()) return true;
    await new Promise((resolve) => setTimeout(resolve, interval));
  }

  throw new Error(`Condition not met within ${timeout}ms`);
}

/**
 * Attach a console listener to the given page and collect all log messages.
 * Must be called before navigating to capture early logs.
 *
 * @param {import("@playwright/test").Page} page - Playwright page instance
 * @returns {{ type: string, text: string, timestamp: string }[]} Mutable log array
 */
function captureConsoleLogs(page) {
  const logs = [];

  page.on("console", (msg) => {
    logs.push({
      type: msg.type(),
      text: msg.text(),
      timestamp: new Date().toISOString(),
    });
  });

  return logs;
}

/**
 * Take a full-page screenshot with an auto-generated timestamped filename.
 *
 * @param {import("@playwright/test").Page} page - Playwright page instance
 * @param {string} name - Base name for the screenshot file
 * @returns {Promise<string>} Resolved filename of the saved screenshot
 */
async function captureScreenshot(page, name) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `${name}-${timestamp}.png`;

  await page.screenshot({ path: filename, fullPage: true });
  console.log(`Screenshot saved: ${filename}`);

  return filename;
}

/**
 * Wait for navigation to complete after triggering an action.
 * Combines the action and navigation wait to avoid race conditions.
 *
 * @param {import("@playwright/test").Page} page - Playwright page instance
 * @param {() => Promise<void>} action - Async action that triggers navigation
 * @param {{ waitUntil?: "load" | "domcontentloaded" | "networkidle" | "commit" }} [options]
 * @returns {Promise<void>}
 */
async function waitForNavigation(
  page,
  action,
  options = { waitUntil: "networkidle" },
) {
  await Promise.all([page.waitForNavigation(options), action()]);
}

/**
 * Trigger an action and capture the first matching network response.
 *
 * @param {import("@playwright/test").Page} page - Playwright page instance
 * @param {string | ((res: import("@playwright/test").Response) => boolean)} urlOrPredicate - URL substring or response predicate
 * @param {() => Promise<void>} action - Async action that triggers the request
 * @returns {Promise<import("@playwright/test").Response>} The captured response
 */
async function waitForResponse(page, urlOrPredicate, action) {
  const predicate =
    typeof urlOrPredicate === "string"
      ? (res) => res.url().includes(urlOrPredicate)
      : urlOrPredicate;

  const [response] = await Promise.all([
    page.waitForResponse(predicate),
    action(),
  ]);
  return response;
}

module.exports = {
  waitForCondition,
  captureConsoleLogs,
  captureScreenshot,
  waitForNavigation,
  waitForResponse,
};
