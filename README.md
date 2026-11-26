# Feedback Studio

A responsive, static feedback frontend with a project selector, star rating, and two feedback fields. It calls a separately hosted REST API directly from the browser.

## Run locally

Use Node.js 26+ and npm:

```sh
npm ci
npm run dev
```

Open http://localhost:3000. Start the external API separately. There is no build step or environment file. Serve the app through HTTP rather than opening index.html directly.

`npm start` serves public/ on the host's PORT, defaulting to 8080. `npm run dev` uses port 3000. Both commands disable asset caching for configuration changes.

## Configure the API

Edit [public/config.js](public/config.js):

```js
export const api = {
  baseUrl: "https://localhost:7026",
  healthPath: "/health",
  messagesPath: "/messages",
};
```

Paths are appended to the base URL, including any base path. For deployment, set a public HTTPS API URL before publishing: localhost refers to the visitor's own machine. Configuration is public and must not contain secrets.

The API must allow the frontend's origin through CORS. Local development uses http://localhost:3000; production uses the deployed frontend origin. Allow GET and POST, the Content-Type header, and the OPTIONS preflight. Trust the API's HTTPS development certificate in the browser when working locally.

On initial load, GET /health starts in parallel with fetching the project list. A failed check or a 15-second timeout displays a status message without blocking the form.

Submission sends POST /messages with Content-Type: application/json and a PublishMessageRequest body:

```json
{
  "message": "Project: FootieLineup (footielineup)\nRating: 4/5\n\nWhat do you love about it?\nEasy to use.\n\nWhat could be even better?\nMore filters.",
  "subject": "New FootieLineup feedback"
}
```

The subject names the project. The message includes the project name and ID, rating, and both trimmed feedback fields. The frontend sends both properties as strings; the API schema also accepts a null subject.

Any 2xx response confirms submission, including empty or plain-text responses. HTTP errors, network errors, and timeouts retain the form contents for retry. Submission times out after 15 seconds. After an uncertain timeout, check delivery before resubmitting to avoid duplicates.

## Configure projects

Edit [public/projects.json](public/projects.json). Each entry has an id, name, description, and HTTP(S) url. Use null for url to hide its link. Keep IDs unique and include at least one project. These files are served directly; refresh the page after changes.

Visitors must choose a rating from 1 to 5 and complete both feedback fields. Each field accepts up to 2,000 characters. Validation and character counts run in the browser.

## Test

```sh
npx playwright install chromium
npm test
```

Playwright starts a static server on port 3100 and runs desktop/mobile tests with a mocked external API. Tests cover the JSON payload, required fields, rating, reset, overflow, parallel initialization, service errors, and submission retries. They do not send real feedback. For a preinstalled Chromium binary, set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH. Reports and test output are ignored by Git.

## Deploy

Any static web host can serve the contents of public/. Publish config.js and projects.json alongside index.html, app.js, and styles.css. Files currently assume hosting at the domain root. Set the production API URL and CORS origin before testing delivery.

Hosting is provisioned separately from publishing the frontend:

- [AWS: private S3 + CloudFront Free](terraform/README.md), published from develop using GitHub OIDC.
- [Azure: Static Web Apps Free](terraform/azure/README.md), published from main using a deployment token.

Run Terraform in the relevant directory, configure the GitHub settings from its outputs, then run the deployment workflow. Only public/ is uploaded; npm and the local static server are development tools.

Existing infrastructure needs a migration plan review: applying these configurations retires Beanstalk and Container Apps resources. See each guide for resource removal, publishing order, and hostname changes.

Both deployment workflows run browser tests before publishing. Deployment smoke checks fetch static assets. Live API connectivity, CORS, and actual message delivery require verification with your separately hosted API.

## Repository layout

```text
public/                  Static page, styles, browser code, and configuration
e2e/                     Playwright browser tests
playwright.config.js     Desktop/mobile test settings and static test server
.github/workflows/       AWS and Azure deployment workflows
terraform/               AWS frontend hosting
terraform/azure/         Azure frontend hosting
```
