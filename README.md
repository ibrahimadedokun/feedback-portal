# Feedback Studio

A responsive feedback portal for **FootieLineup**, built from the supplied wireframe. A warm, editorial desktop layout becomes a focused single-column form on mobile.

## Run locally

Requires **Node.js 22 or newer** and npm. No build step, database, or frontend framework is needed.

```sh
npm ci
cp .env.example .env
npm run dev
```

Open `http://localhost:3000`. Use `npm start` to run without the development watcher. Environment changes require a server restart.

The example config starts in **demo mode**. Demo submissions are validated, but **not stored or sent to AWS**. Both the form and confirmation explicitly say this. Mock AWS values and the mock project URL are included so you can replace them later; they are not working credentials or a real endpoint. `.env` is ignored by Git.

## Features

- Project selector and configurable application link.
- Accessible native radio buttons for five colour-coded stars, with hover previews and keyboard navigation.
- Two required feedback fields, character counts, and client/server validation.
- Loading, sending, success, retry, and connection-error states.
- Feedback is kept in the form after delivery errors; successful submissions can be reset.
- Server-side AWS SNS integration; no credentials or topic ARN are exposed in frontend configuration.
- Request size limits, basic in-memory rate limiting, same-origin checks, and security headers.
- Locally served assets, system fonts, and CSS/SVG artwork; no external font or image services.

## Configuration

Edit `.env` using `.env.example` as a reference:

| Variable | Example / purpose |
| --- | --- |
| `PORT` | `3000` |
| `FEEDBACK_MODE` | `demo` for local testing, `sns` for real delivery |
| `FOOTIELINEUP_URL` | `https://footielineup.example.com` — **mock**, replace with the real app URL; omit to hide the link |
| `AWS_REGION` | `eu-west-2` — replace if your SNS topic is in another region |
| `SNS_TOPIC_ARN` | `arn:aws:sns:eu-west-2:123456789012:footielineup-feedback` — **mock**, replace the account, region, and topic |
| `AWS_ACCESS_KEY_ID` | `MOCK_ACCESS_KEY_ID_REPLACE_ME` — **mock**, replace securely for local credentials |
| `AWS_SECRET_ACCESS_KEY` | `MOCK_SECRET_ACCESS_KEY_REPLACE_ME` — **mock**, replace securely for local credentials |
| `AWS_SESSION_TOKEN` | Blank; supply only when using temporary AWS credentials |

For deployed environments, use an IAM role and the AWS SDK default credential provider chain instead of static keys. **Remove the mock AWS credential variables when using a role or profile** so they do not override it. Never commit real credentials; use your host's secure environment settings or secret manager.

### Enable real SNS delivery

1. Create a **standard SNS topic** in your chosen AWS region.
2. Add an email, HTTPS, SQS, or other supported subscription. Confirm subscriptions where required (email subscribers must accept the confirmation email).
3. Grant the server's AWS identity permission to publish to that topic. Example least-privilege policy (replace the mock ARN):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sns:Publish",
    "Resource": "arn:aws:sns:eu-west-2:123456789012:footielineup-feedback"
  }]
}
```

4. Replace the mock settings, set `FEEDBACK_MODE=sns`, and restart the server. Permit outbound HTTPS to the SNS endpoint for the configured region (for example `sns.eu-west-2.amazonaws.com`).
5. Submit a test and confirm receipt at your subscriber. A success response means SNS accepted the message; downstream delivery depends on the subscription.

The SNS message is JSON containing `id`, `project`, `rating`, `likes`, `improvements`, and `submittedAt`. No real SNS delivery has been tested with the mock settings. Missing SNS configuration returns 503; an AWS publish failure returns 502. Neither displays a successful delivery confirmation.

## Project list

The server's `projects` array in `server.js` defines the selector options. FootieLineup is included. Add an `id`, `name`, `description`, and valid HTTP(S) `url` for each additional project. IDs are validated on submission.

## Tests

```sh
npm test
npx playwright install chromium
npm run test:browser
```

If Chromium is already installed, use it without downloading another browser:

```sh
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium npm run test:browser
```

The backend suite covers demo mode, SNS publishing with a mock publisher, payload validation, missing configuration, delivery failures, request limits, and cross-origin protection. Browser tests cover desktop and mobile submission, validation, rating, reset, error recovery, and overflow checks. Screenshots are written to the ignored `test-results/` directory.

Verified during development: **5 backend tests and 4 browser tests passed**, using system Chromium. Live AWS delivery remains unverified until real settings are supplied.

## API

- `GET /api/config`: public project metadata and delivery mode.
- `POST /api/feedback`: JSON `{ "project": "footielineup", "rating": 5, "likes": "…", "improvements": "…" }`. Rating must be an integer from 1–5; both text fields must contain non-whitespace text and be at most 2,000 characters. Request bodies are limited to 16 KiB.

## Deployment notes

Run this as a Node service behind an HTTPS reverse proxy, binding to the port supplied by your host. There is no separate static build output. No feedback is retained locally. The current limiter allows 20 requests per connection IP per minute and is process-local; behind a proxy it may group visitors together. Use shared rate limiting, bot protection, monitoring, and appropriate privacy/retention policies before a high-traffic public launch. SNS publish retries and uncertain network responses can result in duplicate messages; consumers can deduplicate using each message's `id`. A manually retried submission receives a new ID.

## Layout

```text
public/                 Responsive UI, styles, and browser interactions
server.js               Static server, validation, and SNS publisher
.env.example            Editable mock configuration
playwright.config.js    Desktop/mobile browser-test configuration
test/                   Backend tests
e2e/                    Browser tests
```
