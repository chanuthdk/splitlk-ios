# SplitLK

Receipt-scanning bill splitting for group travel in Sri Lanka.

Photograph a bill, and the app reads the line items and prices on-device, categorises each
one with a classifier trained on Sri Lankan item names, and works out who owes what. When
it is time to settle, it reduces the debts to the smallest possible set of payments.

Built for the iOS Application Development module, BSc (Hons) Computing, NIBM.

---

## Why

Splitwise and Settle Up handle the ledger well, but every line item is typed by hand. That
is exactly the work people avoid, so the equal split wins by default — which is wrong the
moment one person skips the drinks or two share a room. SplitLK removes the typing.

The Sri Lankan focus is technical, not decorative. Apple's pre-trained word embeddings have
no useful vector for *kottu*, *watalappan* or *thambili*, so an off-the-shelf similarity
approach misfiles most of a local receipt. Categorising them correctly needs a model trained
on local vocabulary.

---

## What it does

- **Scans a receipt.** Detects the bill in a photograph, corrects its perspective, reads the
  text, and extracts line items with prices.
- **Catches duplicates.** A perceptual fingerprint of each receipt stops the same bill being
  entered twice when two people both photograph it.
- **Categorises items** with an on-device Core ML classifier, with a keyword fallback and
  per-item corrections that take priority and persist.
- **Splits exactly** — equally, per item, or custom — with service charge and tax
  apportioned and no rounding loss.
- **Settles in the fewest payments** using a minimum cash flow calculation.
- **Syncs across devices** through Firestore; others join with a short invite code. Works
  fully offline.
- **Home-screen widget** showing what you are owed and what you owe.
- **Siri shortcuts** for logging an expense and checking a balance.
- **Face ID lock**, re-locking whenever the app backgrounds.
- **Local reminders** for outstanding balances, with inline actions.

<!-- Add 4–6 screenshots here once you have them. Suggested:
     groups list · receipt scan · bill editor with items read · settle up · insights · widget
     ![Groups](docs/screenshots/groups.png)
-->

---

## Running it

**Requirements:** Xcode 16 or later, iOS 18 simulator. No paid Apple Developer account needed.

```bash
git clone https://github.com/chanuthdk/splitlk-ios.git
cd splitlk-ios
open SplitLK/SplitLK.xcodeproj
```

Let Swift Package Manager resolve Firebase on first open, then select an iPhone simulator and
run. The app opens to an empty state with a **Load sample data** button.

### Demonstrating the features that need setup

| Feature | What to do first |
|---|---|
| Receipt scanning | Save a receipt photo into the simulator's Photos app (drag and drop onto the simulator window) |
| Face ID | Simulator → Features → Face ID → **Enrolled**, then choose **Matching Face** when prompted |
| Sync | Run on two simulators; create a group on one, join with its invite code on the other |
| Notifications | Settings tab → turn on settle-up reminders → **Send a test reminder** (fires in 10s) |
| Widget | Long-press the simulator home screen → add the SplitLK widget |
| iPad layout | Switch the run destination to any iPad simulator |

---

## The machine learning model

The trained model is **not committed** — it is a build artefact. The training data and
instructions are in [`MLTraining/`](MLTraining/).

The app runs without it: `CategoryClassifier` loads the model by filename at runtime and
falls back to keyword matching if it is absent. The Settings tab reports which path is live
("On-device model" or "Keyword matching").

To train and add it:

1. Xcode → Open Developer Tool → **Create ML** → New Document → **Text Classification**
2. Name it `ItemCategoryClassifier`
3. Drag `MLTraining/item-categories.csv` onto **Training Data**; text column `text`, label
   column `label`
4. Algorithm **Maximum Entropy**, **25 iterations** (the default 10 stops before convergence
   on six classes)
5. Train, then **Output → Get** and save the `.mlmodel`
6. Drag it into `SplitLK/SplitLK/Resources` with **Copy items if needed** and the **SplitLK**
   target ticked

### How classification works

Three tiers, cheapest and most certain first:

1. **A user correction** for that item name, if one exists
2. **The trained model**, but only above a confidence floor of 0.45 — a classifier always
   returns its best label, so without a floor a misread line becomes a confident wrong
   category instead of an honest "other"
3. **Keyword matching**, resolving overlaps by longest match so `ice cream` beats a stray
   `cream` and `service charge` is not read as food

`MLTraining/README.md` documents a 99%-training-against-74%-validation overfit, its cause
(label conflicts created by the data generator, not a modelling error) and the fix.

---

## Backend

Cloud Firestore with anonymous Firebase Authentication. No custom server.

| | |
|---|---|
| Project ID | `splitlk` |
| Bundle ID | `com.chanuth.SplitLK` |
| SDK | `firebase-ios-sdk`, pinned to 12.x |

Each group is a document under `groups/`, keyed by UUID, with `members`, `bills`, `items`
and `settlements` as subcollections. The group document carries the invite code and the list
of auth identifiers allowed to read and write it.

**Amounts are stored as strings, not numbers.** Firestore represents numbers as IEEE 754
doubles, which would reintroduce exactly the floating-point error `Decimal` was chosen to
avoid.

No credentials are needed to verify sync works — the app authenticates anonymously. Run it on
two simulators and join with an invite code.

---

## Architecture

SwiftUI throughout, with services kept free of any SwiftUI dependency so they can be tested
in isolation. View models exist only where a screen holds real editing state before commit.

```
SplitLK/
  App/         SplitLKApp, PersistenceController
  Models/      Core Data extensions, Money, Palette, GroupStyle
  Services/    scanning, parsing, classifying, calculating, syncing
  ViewModels/  BillEditorViewModel, GroupEditorViewModel
  Views/       Groups, Bills, Shared
SplitLKWidget/ widget extension (reads a shared App Group snapshot)
SplitLKTests/  50 tests
MLTraining/    classifier training data and instructions
```

Seven Core Data entities: `CDGroup`, `CDMember`, `CDBill`, `CDItem`, `CDItemShare`,
`CDBillShare`, `CDSettlement`.

Money is `Decimal`, never `Double`.

### Frameworks

| Framework | Used for |
|---|---|
| SwiftUI | The entire interface |
| Core Data | Local persistence |
| Vision | Document detection, text recognition, duplicate fingerprinting |
| Core ML / Natural Language | On-device item categorisation |
| Create ML | Training the classifier |
| Core Image | Perspective correction |
| WidgetKit | Home-screen balance widget |
| App Intents | Siri and Shortcuts |
| UserNotifications | Local reminders with inline actions |
| LocalAuthentication | Face ID / Touch ID lock |
| Swift Charts | Spending visualisations |
| PhotosUI | Receipt selection |
| Observation | View model and service state |
| Swift Testing | Test suite |
| Firebase | Anonymous auth and Firestore sync |

### iPhone and iPad

The groups screen is a `NavigationSplitView` in its balanced style: a persistent sidebar
beside the open group on iPad, collapsing to push navigation on iPhone — one definition, not
two view hierarchies. The rest of the app is deliberately identical on both, because forms
and lists gain nothing from a second column.

---

## Tests

```bash
# In Xcode: Cmd+U, with the SplitLK scheme selected
```

50 tests across four files, concentrated where an error costs money or trust: the receipt
parser, the category classifier, insights aggregation, and the split and settlement
calculators.

`CategoryCorrectionTests` is marked `@Suite(.serialized)` — those tests all write to the same
`UserDefaults` key, and under Swift Testing's default parallel execution they were clearing
each other's state mid-run.

---

## Known limitations

- Capture is from the photo library rather than a live camera, since development was
  Simulator-only. The Vision pipeline is unchanged by this and accepts camera output directly.
- The classifier is trained on generated variants of seed terms rather than genuine recognised
  text from a corpus of real receipts.
- The parser assumes a broadly two-column receipt layout.
- Only LKR is fully exercised, though other currencies can be selected per group.
- Anonymous auth means a lost device identity cannot be recovered.

---

## Note on AI assistance

Generative AI (Claude) was used to assist with code generation during implementation, with
the module lecturer's prior approval by email. Commits carry their true authorship and dates;
the development history is open for inspection.

---

**Chanuth** · COBSCCOMP251P-031 · BSc (Hons) Computing, Batch BSCCOMP25.1P
National Institute of Business Management
