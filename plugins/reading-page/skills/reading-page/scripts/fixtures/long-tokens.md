# Long tokens: phone overflow fixture

Date: 2026-10-07. Fixture for browser_check.sh: every element below holds a long unbroken token, so a 390-wide page must wrap it, never scroll sideways. https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789

## Bottom line

The page wraps https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 inside the bottom-line box.

## Findings

A paragraph with a bare URL https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 and a hash sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef in the middle of prose.[^1]

- A list item with https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789
- A list item with a mark [V, https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789]

**Main risks:**

- A callout item with sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

| Option | Link | Hash | Note |
|---|---|---|---|
| One | https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 | sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | short |
| Two | https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 | sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | short |
| Three | https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 | sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | short |
| Four | https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789 | sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | short |

## 日本

A Unicode heading. [Link to it with a percent-encoded fragment](#h-%E6%97%A5%E6%9C%AC) and [back to findings](#findings).

## Sources

- https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789

[^1]: A footnote whose source is https://example.com/aVeryLongUnbrokenPathSegmentWithoutAnySeparators1234567890abcdefghijklmnop?token=abcdef0123456789abcdef0123456789
