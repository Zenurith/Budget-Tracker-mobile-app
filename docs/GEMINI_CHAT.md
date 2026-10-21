# Gemini wishlist chat

Open Protected funding → Open guilt-free wishlist → Ask Gemini (chat icon).
Sending a question shares its text, recent conversation context, and a limited current funding summary with
Google Gemini. The screen explains this before sending. No names, account IDs,
transaction histories, wishlist notes, or credentials are added to that summary.
Stale funding omits available-cash figures.

Follow-up questions include up to three recent exchanges (six messages, each
bounded to 2,000 characters) with a fresh funding summary. Long assistant replies
are shortened for context. History is untrusted context for identifying a wish,
not a source of current cash figures. Conversations stay in memory only and clear
on funding/session changes, app resume, leaving the screen, or New conversation. Gemini cannot save wishes, reserve cash, or purchase;
use the existing wishlist editor to review and save an item.

Backend configuration: GEMINI_API_KEY and optionally GEMINI_MODEL
(default gemini-3.5-flash-lite). Start the backend with its existing .env loading
command (uvicorn app.main:app --env-file .env). Never put the key in Flutter.
POST /wishlist/chat requires authentication, limits messages to 2,000 characters,
uses a 25-second provider timeout, and limits each owner to 20 requests/minute
per server process. Multi-worker deployments need a shared gateway quota for a
global spending cap. Provider quota and malformed/blocked replies produce retryable
errors; provider response bodies and API keys are not exposed.

No chat persistence, database migration, or external financial actions.
Implementation follows Google's generateContent API:
https://ai.google.dev/api/generate-content

Validated with one generic live request using the configured backend key.

## Reviewable drafts and funding cards

Gemini returns a validated structured reply with an optional single wish draft
(name, positive total cost in minor units, matching account currency). Missing,
ambiguous, multiple-item or foreign-currency requests should prompt clarification;
the user must check all extracted details. Invalid structured replies are rejected.

For drafts, the server reloads funding after the provider response and calculates
available-to-reserve cash, additional funding needed, and readiness using existing
wishlist rules. Missing/stale inputs suppress numeric amounts. A new draft always
has zero reserved cash; even a zero funding gap does not mean purchase readiness.

Review wish draft opens the existing editor with name and cost prefilled. Saving
requires its existing confirmation and revision checks. No reservation or purchase
is created by chat. Cards clear on another question, funding/account changes,
resume, or after one minute. Card expiry preserves conversation history; earlier
replies are explicitly labeled as potentially outdated. Editing a draft does not recalculate its old card;
review the saved wishlist item's current readiness after saving.
