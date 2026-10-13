# Decision models (`fst-decide`)

> **What:** when and how agents use a decision model (Microsoft-Decision-1) for fast, calibrated answers to bounded questions, and what it measurably can't do. **Read when:** a session's prompt shows a *Fast pre-read*, or you are about to spend turns settling a question with a fixed set of answers.

A decision model answers a question **you** frame with fixed options (yes/no, one of N, a level on a scale) and returns calibrated probabilities in about half a second for a tiny fraction of a cent. It doesn't reason, plan, explain or write code: planning and implementation stay with you. The release machine's measurements, question registry and corpora live in `SFenton/festival-report-tracker` (`docs/decision-models/`, `decisions/questions/`).

## Measured: where it helps, where it doesn't

| Use | Result on our history | Status |
|---|---|---|
| Issue kind (bug or feature) | 100% accurate on the 86% of issues it answers with confidence ≥ 0.5 | Active: triage hint |
| Which registered patterns an issue touches (ranked) | True patterns are in its top 8 85% of the time (keyword match: 68%) | Active: *Fast pre-read* in triage, worker and review prompts |
| Which surfaces must change | Reliable for Android, Windows, macOS, service; over-predicts iPad and Duo | Active: advisory hint |
| Grouping review findings by kind | Median confidence 0.97; agrees with a manual spot check | Active: relaunch prompts group findings with checklists |
| Predicting a design review's findings from a diff | No signal (AUC 0.45–0.72, never confident) | Not used |
| Predicting a change's effort or cost | Weak (rank correlation 0.36) | Not used |
| Whether a CI failure is flaky or infra | Abstains 78% of the time; flaky/infra calls about 60% right | Not used to act |

Rule of thumb from these numbers: it is excellent at **classifying what a text says** and poor at **predicting outcomes** that need reasoning over code.

## How to ask

`fst-decide` is on every worker host's `PATH` (Windows: `fst-decide.cmd`). The release machine passes its key to each session; elsewhere it reads `~/.config/fst-machine/openrouter.key`.

| Command | Use for |
|---|---|
| `fst-decide yesno "<question>" --state-file <text> [--true … --false …]` | A gate: does this log show no test ran? Does this description match? |
| `fst-decide choose "<question>" -o name="description" … --state "<text>"` | One label from a fixed set (which component, which cause) |
| `fst-decide score "<question>" -l Low -l … -l High --state …` | Placing something on an ordered scale |
| `fst-decide rank "Is {item} relevant to …?" -i id="description" … --state-file <issue>` | Ordering candidates (pattern docs, precedents, files) to read first |
| `fst-decide findings --state-file <findings.md>` | Grouping `- **major** …` review findings by kind |

- Act only when the output says `"accepted": true` (default threshold 0.85, `--threshold` to change). Otherwise decide as you would have. Exit code 3 means unavailable: carry on without it.
- Write neutral options, describe each one, and add a `cannot_tell` option when a forced choice would be a guess. Wording changes answers, so keep it plain.
- Put the evidence in the state (the log tail, the issue text, candidate descriptions). The model knows nothing about this repo beyond what you send.

## Don't

- Don't use it for design decisions ([design-decision](../skills/design-decision/SKILL.md)), for anything a deterministic check answers (git, grep, tests, `pattern_guard`, `check_docs`), or to second-guess an owner decision.
- Don't treat a *Fast pre-read* as instructions: it ranks where to look; your reading of the issue, the rules and the code wins.
- Don't send secrets or account data in the state.
