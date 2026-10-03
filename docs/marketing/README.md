# Marketing

Sogda's marketing workspace, kept by **agent-5 (Marketing & Media)**
([`developer-agents/agent-5/`](../../developer-agents/agent-5/README.md)).
The work is tracked on GitHub: label `marketing`, milestones **MK1 ·
Marketing foundations** and **MK2 · Play launch campaign**, and lane M on the
team board.

## The rules, in short
- **Facts come from data.** Read [`docs/05-dev-guide/site-facts.json`](../05-dev-guide/site-facts.json) and [`store-listing.md`](../05-dev-guide/store-listing.md), and never type a number.
- **No price, "free", rating or user count.** Goethe and telc are named only to describe.
- **Nothing is posted or sent without the owner.** agent-5 prepares, and the owner publishes.
- **Five languages:** en, de, bn, pl and ru, each copy with its native review.
- **A fact is a token,** like `{totals.words}`, never a typed number. `tools/tests/test_marketing_docs.py` checks every file here.

The full rules are in agent-5's README.

## What lives here
| File | What | Issue |
|---|---|---|
| [`plan.md`](plan.md) | **The launch plan: start here.** Goals, gates, audiences, channels, phases, measuring, risks and the owner's decisions | #1201–#1204 |
| [`channels.md`](channels.md) | Where each audience is: channels, sizes, rules, active hours | #1201 |
| [`competitors.md`](competitors.md) | How competing apps market themselves, and what to copy or avoid | #1202 |
| [`messaging.md`](messaging.md) | One message per audience and channel, with its proof points | #1203 |
| [`calendar.md`](calendar.md) | What goes out, where, in which language and when, around launch day | #1204 |
| [`brand.md`](brand.md), [`brand.json`](brand.json) | Frames, type, colours and safe areas per format: the values in `brand.json`, which the tools read through `tools/media/brand.py` | #1209 |
| `features.md` | The app's selling points and gaps, seen as a learner | #1208 |
| [`posts/<yyyy-ww>.md`](posts/) | Each week's post drafts and the owner's due-list, made by `tools/media/posts.py --week <-3…rhythm> --monday <date>` from the calendar and the messaging, every number filled from `site-facts.json` | #1207 |
| `launch/` | The launch-day kit | #1210 |
| `outreach.md` | The send-list and its tracking | #1212 |
| [`results.md`](results.md) | What each post did, from the numbers the owner pastes | (ongoing) |
| `research/` | The dated research behind the plan, with a source for every number | #1201, #1202 |

Each file comes from its issue. **The tools** that render
images and videos are in [`tools/media/`](../../tools/): `stills.py` (#1205), a
template in every format and language; `video.py` (#1206), a short video from an
emulator recording (`tools/media/videos/<name>.yaml`: the steps, the cut and timed
captions per language, numbers as facts' `{tokens}`; `takes`, one learner per meaning language, #1355), framed 9:16 and 16:9, recorded on emulator-5556 (`--serial`);
`feature_graphic.py` (#1200). **The renders**
are on the [`media`](https://github.com/MdRahmatUllah/DeutschPlan/tree/media)
branch.
