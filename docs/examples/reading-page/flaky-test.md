<!-- Made-up example for the README picture. No real project, person or company. -->
---
title: Why the sign-in test fails one run in twenty
date: 2026-11-14
author: Claude
status: reference
why: A made-up example for the README picture. No real project, person or company.
---

# Why the sign-in test fails one run in twenty

## Bottom line

**The test fails when its session cookie expires mid-run; sign-in itself works.** The test sets a 30-second session and the slowest runs take 34 seconds, so about one run in twenty outlives its own cookie. A five-minute test session fixes it without touching the product.

## 1. What fails

The sign-in test failed 41 times in the last 800 runs (5.1%). Every failure is the same assertion: the dashboard sends the user back to the sign-in page after the third step.

| Runs | Failed | Median run time | Slowest run |
|---|---:|---:|---:|
| Last 800 | 41 | 22 s | 34 s |
| Runs over 30 s | 41 | 31 s | 34 s |
| Runs under 30 s | 0 | 21 s | 29 s |

**Main risks:**
- A five-minute session could hide a real expiry bug. A separate test covers expiry with a fixed clock.

## 2. What we checked

- Re-ran each failing run with the same seed: all 41 passed with the clock frozen. [V]
- Compared the server logs: each failure shows `session expired` 30 seconds after sign-in. [V]
- Looked for a slow dependency: the slow runs start while the database container is still warming up. [I]

**Recommendation:** set the test session to five minutes, and start the test only after the database answers its health check.

## Sources

- Test history, last 800 runs.
- Server logs for the 41 failed runs.
