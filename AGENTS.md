# AIWindow Agent Guide

## Scope

AIWindow is an iOS 17+ SwiftUI app. The current repository contains the AI HOT
news client and user-driven LINUX DO search/browser flows. A chatbot and app
backend do not exist and must not be implied by documentation or UI.

Read `README.md`, `docs/architecture.md`, and `apps/ios/README.md` before making
behavioral changes.

## Service Boundaries

- Keep AI HOT attribution, canonical links, and original-source links visible.
- Do not poll the same complete AI HOT URL more than once per 60 seconds. Reuse
  cached data, conditionally revalidate expired data, and honor `Retry-After`.
- LINUX DO access must remain user-driven through a normal browser or
  `WKWebView`. Do not add crawlers, background monitoring, bulk extraction,
  iframe embedding, or redistribution of forum posts and images.
- Keep search-engine web data ephemeral. Persistent WebKit data is reserved for
  user-driven `linux.do` top-level pages, must remain clearable in Settings, and
  must never be inspected, logged, exported, or included in backups.
- Do not commit API keys, Apple Team identifiers, signing material, device
  identifiers, cookies, personal data, absolute local paths, or email addresses.
- Keep `DEVELOPMENT_TEAM` out of `project.pbxproj`; each developer selects a
  signing team locally.

## Validation

Run from `apps/ios`:

```sh
xcodebuild \
  -project AIWindow.xcodeproj \
  -scheme AIWindow \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For tests, first select an installed simulator listed by:

```sh
xcodebuild -project AIWindow.xcodeproj -scheme AIWindow -showdestinations
```

Before committing, run `git diff --check` and
`./scripts/public_release_audit.sh` from the repository root. Changes affecting
network behavior also require the full `AIWindowTests` suite.
