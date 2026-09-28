# Song Detail — Android notes

> **What:** Android implementation state and decisions for Song Detail and the full song leaderboard. **Read when:** changing Song Detail on Android. Behavior: [spec.md](spec.md).

## Implemented

- Song resolved by ID (debug: or exact title) against the current catalogue; header art + title + `artist · year · duration` (+ album); the shared backdrop shows this song's static dimmed cover while visible.
- Intensity card: every **charted** instrument (even hidden ones) with icon, label and the branded meter (raw 0–6).
- One lazily-started ten-row preview per **visible** charted instrument (`GET /api/leaderboard/{id}/{instrument}?top=10&offset=0`, one GET per card only when composed): loading / inline service status / "No scores yet" / rows (rank, name, FC or tinted accuracy, score) + **View Full Leaderboard** after the rows (web order).
- `/songs/:songId/:instrument`: 25-row pages with Previous/Next and past-the-end page correction.

## Open

Paths sheet, Shop action, selected-player spotlight and score history, band previews, row → player navigation, Quick Links.
