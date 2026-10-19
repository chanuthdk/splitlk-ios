# Item category classifier

Training data and instructions for the on-device model that categorises
receipt lines into food, drinks, transport, groceries, accommodation or other.

## Why a trained model rather than word embeddings

Apple's built-in word embeddings have no useful vector for "kottu",
"watalappan" or "thambili", so a similarity-based approach misfiles most
of a Sri Lankan receipt. Training on local item names is the point of the
exercise, not incidental to it.

## Data

`item-categories.csv` — 1,827 labelled rows, two columns: `text`, `label`.

| Label | Rows |
|---|---|
| food | 582 |
| groceries | 339 |
| drinks | 311 |
| other | 225 |
| transport | 201 |
| accommodation | 169 |

Each seed term is expanded into the shapes OCR actually produces: upper
case, lower case, spacing removed or doubled, truncation, trailing size
markers such as "Large" or "(L)", and common character confusions (o→0,
l→1, S→5). That matters because the model sees recognised text, not menu
text.

### A note on the first attempt

An earlier version of this data also emitted single words pulled out of
each term — the last word, the first two words. That produced direct label
conflicts: "Ticket" appeared under both transport (Train Ticket) and other
(Cinema Ticket), and "Rice" under both food (Fried Rice) and groceries
(Samba Rice). A classifier cannot learn a contradiction, so it memorised
the rest instead: **99% training accuracy against 74% validation**, a
textbook overfit.

The generator now keeps only variants that preserve the label, and drops
any text that still ends up under more than one category. Nothing is
dropped by the current rules, which is the point — the ambiguity was
created by the expansion, not present in the source terms.

## Training

1. Open **Create ML** (Xcode → Open Developer Tool → Create ML)
2. New Document → **Text Classification** → Next
3. Name it `ItemCategoryClassifier`
4. Drag `item-categories.csv` onto **Training Data**
5. Set the text column to `text` and the label column to `label`
6. Leave Validation on **Automatic** so a split is held out
7. Algorithm: **Maximum Entropy** — fast to train and small to ship,
   which suits short item names better than a transformer would
8. Set **Iterations** to **25**. The default 10 stops before the model has
   converged on six classes
9. **Train**, then check the Evaluation tab

Note the validation accuracy; it belongs in the report, along with the
per-class breakdown. A category scoring noticeably worse than the others
is a finding worth stating rather than hiding — `other` is the usual
culprit, being a catch-all with no consistent vocabulary.

## Adding it to the app

1. In Create ML, **Output** tab → **Get** → save `ItemCategoryClassifier.mlmodel`
2. Drag it into the Xcode project, into `SplitLK/SplitLK/Resources`
3. Tick **Copy items if needed** and the **SplitLK** target
4. Build

`CategoryClassifier` loads it by filename at runtime, so no generated class
is referenced and nothing needs rewiring. With the model absent the app
falls back to keyword matching, which is why it works before this step and
would keep working if the model were ever removed.

Settings shows which path is live: "On-device model" or "Keyword matching".

## What to say in the viva

- The model runs entirely on-device; no item name leaves the phone.
- Seed data flows through an Apple SDK as required: receipt image → Vision →
  parsed text → Core ML → category.
- User corrections are stored and take priority over the model, so a wrong
  guess only has to be fixed once. That is cheaper and far more predictable
  than retraining on-device, and it means the app improves per user without
  any further training step.
