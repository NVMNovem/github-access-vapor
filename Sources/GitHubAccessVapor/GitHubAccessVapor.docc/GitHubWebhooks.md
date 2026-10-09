# Webhooks

Receive GitHub deliveries, verify their signature, and route them to handlers.

## Overview

```swift
try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"),
                          path: "github", "webhook")

app.gitHubEvents.on(.release) { event, request in
    guard event.action == .published else { return }
    request.logger.info("\(event.repository.fullName) released \(event.release.tagName)")
}
```

`configureWebhooks` mounts a single `POST` route, defaulting to `/github/webhook`. Handlers
registered on `app.gitHubEvents` — a ``GitHubEventDispatcher`` — can be added before or after it;
nothing reaches them until a delivery's signature has verified.

### A secret that arrives after start-up

When the App is created from a manifest, GitHub generates the webhook secret after the server is
already running, and a route cannot be added to a running server. Pass
``GitHubWebhookSecret/provider(_:)`` so the secret is asked for on every delivery. Until it returns
a value, deliveries are refused with `503`, never accepted unverified.

```swift
try app.configureWebhooks(secret: .provider { await secrets.webhookSecret() },
                          path: "github", "webhook")
```

### The signature covers the raw body

GitHub signs the **bytes it sent**, and puts an HMAC-SHA256 of them in `X-Hub-Signature-256` as
`sha256=<hex>`.

Decoding the body and re-encoding it does not round-trip byte-identically — key order, whitespace,
and number formatting all shift — and any such round trip invalidates the signature. The route
therefore reads `request.body.data` under an explicit `.collect(maxSize:)` strategy and verifies
those bytes before anything looks at the payload as JSON. ``GitHubWebhookDelivery/payload`` carries
them through unchanged.

This is the one part of webhook handling that is genuinely subtle. It passes every test written
against a fixture you encoded yourself, and fails only against real deliveries — where it looks like
GitHub is sending bad signatures.

Comparison is constant time, by way of swift-crypto's `HMAC.isValidAuthenticationCode`. CryptoKit is
not used anywhere, because it does not exist on Linux.

### Answering fast

GitHub gives a webhook about ten seconds before it calls the delivery failed. The route verifies,
deduplicates, hands the delivery to a task, and answers — `202 Accepted` for a delivery that was
handed off, `200 OK` for one already seen. Handlers then run for as long as they need, outside the
request.

A handler that throws is logged; the remaining handlers still run.

### Retries are deduplicated

GitHub retries deliveries, and a redelivered event must not run its handler twice. The route
remembers recent `X-GitHub-Delivery` identifiers — a bounded window, 512 by default — and answers a
repeat with `200 OK` without dispatching it.

The window does not survive a restart. A retry arriving across one is vanishingly unlikely, but
handlers that cause side effects should be idempotent regardless.

### Rejections

| Situation | Response |
| --- | --- |
| Missing `X-Hub-Signature-256`, `X-GitHub-Event`, or `X-GitHub-Delivery` | `400 Bad Request` |
| Missing body | `400 Bad Request` |
| Signature does not verify | `401 Unauthorized` |
| Already-seen delivery | `200 OK`, not dispatched |
| Verified delivery | `202 Accepted`, dispatched |

### Events this package does not model yet

``GitHubEventName`` is an open type rather than an enum, so an unrecognised event still arrives.
Handle it by raw name, decoding whatever shape you need:

```swift
app.gitHubEvents.on(event: "workflow_run") { delivery, request in
    let payload = try delivery.decode(MyWorkflowRun.self)
}
```

``GitHubEventDispatcher/onAnyEvent(use:)`` receives every verified delivery, whatever its event.

Adding a first-class event is additive: declare a payload, conform it to ``GitHubWebhookEvent``, and
extend ``GitHubEventKey`` with a matching static property.

### Decode leniently

GitHub adds fields to payloads without warning, and a strict decoder turns a new field into a
rejected delivery. The bundled payload types ignore unknown fields, default the ones that may be
absent, and keep unrecognised `action` values rather than failing on them.

### Testing your handlers

`GitHubAccessVaporTesting` signs fixtures the way GitHub does:

```swift
import GitHubAccessVaporTesting

let signature = GitHubWebhookSigner.sign(body: fixture, secret: "test-secret")
```

Sign the exact bytes you are going to send. ``GitHubWebhookSignatureVerifier`` is public from the
main target too, for asserting that a tampered body is rejected.

## Topics

### Mounting the endpoint

- ``GitHubWebhookSecret``
- ``GitHubWebhookHeader``

### Handling events

- ``GitHubEventDispatcher``
- ``GitHubWebhookDelivery``
- ``GitHubEventName``
- ``GitHubEventKey``
- ``GitHubWebhookEvent``

### Release events

- ``GitHubReleaseEvent``
- ``GitHubRelease``
- ``GitHubRepository``
- ``GitHubInstallationReference``

### Signatures

- ``GitHubWebhookSignatureVerifier``
