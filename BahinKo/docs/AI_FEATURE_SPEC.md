# AI Feature Specification: AI Receipt Scanner

**App:** BahinKo (bill splitting for friends and housemates)
**Feature owner:** renz
**Course requirement:** CC 207B Final Project, AI-Powered Feature (relevance, security, graceful failure, responsible use)

> Sections marked **[verify]** describe behavior taken from the code and tests. Replace or confirm them with your own screenshots and real runs before submitting.

---

## 1. What the feature does

The user photographs a restaurant or store receipt. BahinKo reads the photo, finds each ordered item and its price, and opens the **Assign Items** screen with the items already filled in. The user then corrects anything wrong and assigns each item to the people who shared it.

```
photo ──► 1. On-device OCR (ML Kit) ──► raw text
      ──► 2. Mask personal data (redactForAi)
      ──► 3. AI (Gemini) organizes text into items ──► sanity checks
      ──► Fallback A: rule-based parser if the AI fails, times out, or is unusable
      ──► Fallback B: ScanFailure ──► Retake photo / Enter manually
```

It is **one core feature** of the app: it takes user input (a photo), processes it, and produces a meaningful result (an itemized bill ready to split).

## 2. AI service, model and packages

| Item | Value |
|---|---|
| AI service | Gemini through **Firebase AI Logic** (Gemini Developer API) |
| Model | `gemini-3.5-flash-lite` (`GeminiReceiptAi.modelName`). A fast, low-cost model is enough for reading receipt text. |
| Flutter package | `firebase_ai` 5.2.0 (with `firebase_core` 5.2.0) |
| Abuse protection | `firebase_app_check` 0.5.2 (Android debug provider in development) |
| On-device OCR | `google_mlkit_text_recognition` 0.15.1 (Latin script) |
| Camera | `camera` 0.12.2 |

**Code map**

| Part | File |
|---|---|
| Gemini call, prompt, JSON schema, JSON parsing, privacy masking | `lib/services/receipt_ai_service.dart` |
| Pipeline, timeouts, retry, fallback, answer checking | `lib/services/receipt_scanner.dart` |
| OCR (mobile) and stub (web/desktop) | `lib/utils/receipt_ocr_mobile.dart`, `receipt_ocr_stub.dart` |
| Rule-based fallback parser and non-item filter | `lib/utils/receipt_parser.dart` |
| Screens: entry, camera, scanning (loading/error) | `lib/screens/scan/` |
| Result review ("AI-detected", "Needs review") | `lib/screens/bill/assign_items_screen.dart`, `widgets/edit_item_sheet.dart` |
| Tests | `test/receipt_ai_test.dart`, `test/receipt_parser_test.dart` |

## 3. Inputs and prompts

**Input to the AI:** only the OCR **text** of the receipt, after privacy masking. The photo itself never leaves the phone.

**System prompt (summary of `GeminiReceiptAi.systemPrompt`):**
- Act as a reader of Philippine restaurant and store receipts, knowing the text comes from OCR and may contain typos, broken lines and merged columns.
- Extract `storeName`, `items` (line total in pesos, fix obvious OCR typos, merge items split across lines), `serviceCharge`, `vat`, `discount` and `total`.
- VAT rule: in the Philippines prices usually already include VAT, so `vat` is set only when it is added on top of the items.
- Give each item a `confidence` from 0 to 1. If any digit of a price had to be guessed, confidence must be below 0.6.
- Never turn dates, OR/SI/reference numbers, table numbers, pax, cashier names, terminal/PTU/TIN numbers, subtotal, cash, change or thank-you messages into items. Never invent items. If the text is not a receipt, return an empty list.

**Generation settings:** `temperature: 0` so the same receipt gives the same answer, and a **structured JSON response schema** (`receiptSchema`), so the app never has to guess how to read the reply.

## 4. Sample input and output [verify]

*Illustrative example. Replace with a real scan from your demo device.*

**OCR text (input after masking):**
```
GOLDEN SAMGYUP HOUSE
Date 11/24/2026  10:45PM
Pork Belly x2 @ 350.00      700.00
Soju x3                     180.00
Rice x5 @ 50.00             250.00
Service charge 10%          113.00
TOTAL                      1,243.00
```

**Gemini JSON answer:**
```json
{
  "storeName": "Golden Samgyup House",
  "items": [
    {"name": "Pork Belly x2", "price": 700.00, "confidence": 1.0},
    {"name": "Soju x3",       "price": 180.00, "confidence": 0.9},
    {"name": "Rice x5",       "price": 250.00, "confidence": 1.0}
  ],
  "serviceCharge": 113.00,
  "vat": 0,
  "discount": 0,
  "total": 1243.00
}
```

**What the app shows:** three items labeled **AI-detected**, plus a "Service charge" line that is split among everyone. Items below 0.7 confidence get an orange border and **Needs review**.

## 5. How failures are handled and the fallback

Every step has a time limit, every error becomes a plain-language message, and the user always has a way forward.

| Situation | What happens | What the user sees |
|---|---|---|
| OCR takes longer than 20 s | `TimeoutException` becomes `ScanFailure` | "Reading the photo took too long. Try again." with Retake / Enter manually |
| OCR finds no text (fewer than 5 characters) | `ScanFailure` | "No text found. Retake the photo in good light with the whole receipt in view." |
| Running on web or desktop | OCR stub throws `UnsupportedError` | "Receipt scanning works in the Android app. Enter the items manually." |
| AI call fails fast (for example "model busy") | **Retried once** after 800 ms, if less than half the time budget was used | Still on the loading screen |
| AI takes longer than 15 s (`aiTimeout`) | Falls back to the **rule-based parser** | Orange banner: "The AI took too long, so basic detection was used. Please check every item." |
| AI service unavailable, quota exhausted, or no network | Falls back to the rule-based parser | Banner: "The AI is unavailable right now, so basic detection was used…" |
| AI answer is unusable (empty, bad JSON, no items, more than half the prices missing) | `reviewAiReceipt` returns null, so the parser runs | Banner: "The AI's answer didn't look right, so basic detection was used…" |
| Parser also finds nothing | `ScanFailure` | "No items found on this receipt. Retake the photo or enter the items manually." |

The screen shows a **loading state** (animated scan line and the current step, "Reading…" then "Organizing…"), an **error state** (message plus Retake / Enter manually) and the **success state** (Assign Items). A receipt scanned by the fallback is labeled **Basic detection** instead of **AI-detected**.

**Checks on a successful AI answer (`reviewAiReceipt`):**
- Items that look like labels, dates or numbers (`looksLikeNonItem`) are dropped even if the AI listed them.
- An item with price 0 or confidence below 0.7 is marked **Needs review**.
- If items do not add up to the printed total (tolerance: the larger of 1 peso or 1%), a warning asks the user to check.
- If a discount explains the difference, the app says so and asks the user to edit the discounted item rather than guessing who gets it.

## 6. Known failure cases [verify]

- **Blurry, folded, curved or dark photos**: OCR misreads digits. The model is told to give low confidence when it guesses, so these items get **Needs review**.
- **Handwritten or non-Latin receipts**: OCR uses the Latin script model only.
- **Multi-column receipts** where names and prices merge. The AI usually repairs these; the rule-based fallback may not.
- **VAT ambiguity**: whether VAT is included or added on top varies by receipt. A wrong guess shows up as a total mismatch warning.
- **Discounts** (senior, PWD, promo) belong to one person. The app flags them but cannot know whose they are.
- **Web and desktop**: scanning only works on Android (and iOS). Elsewhere the user enters items manually.
- **Model/quota availability**: if the Gemini model is retired or the quota is used up, every scan falls back to basic detection.

## 7. Why AI was the right tool

Receipts differ by store in layout, abbreviations ("PRK BLLY ST"), multi-line items and quantity formats ("Rice x5", "2 @ 150.00"). Fixed rules (regular expressions) break on every new format and cannot tell an item from a table number or an OR number reliably. A language model understands context, repairs OCR typos and returns a confidence per item. Ordinary logic is still kept where it is the better fit: the rule-based parser as a free offline fallback, and arithmetic checks (item sum against the printed total) that the app does itself instead of trusting the model.

## 8. Security

- **No API key is in the app or the repository.** Firebase AI Logic signs each request with the Firebase project; the Gemini key stays on Google's servers.
- `lib/firebase_options.dart`, `lib/secrets.dart` and `android/app/google-services.json` are in `.gitignore`. Verify with `git log --all -- lib/secrets.dart lib/firebase_options.dart android/app/google-services.json`, which must print nothing.
- **App Check** proves requests come from the real app, so the project's AI quota cannot be used from a script. If App Check fails, the AI is refused and the scanner falls back to basic detection, so the app never breaks.

## 9. Responsible use and privacy (RA 10173)

- **Labeling:** AI-produced items show an **AI-detected** label; fallback items show **Basic detection**.
- **User control:** the user can edit any item's name or price, or flag it, in the Edit Item sheet. Saving clears **Needs review**. Saving or splitting with items still marked **Needs review** asks for confirmation first. The user always decides, not the AI.
- **Data minimization:** only receipt **text** is sent, never the photo. `redactForAi` masks emails (`[email]`) and long digit runs of 10 or more digits (`[number]`), which covers card, account, phone and TIN numbers. Short prices such as "1,250.00" stay readable.
- **No extra personal data** is collected for this feature. Names of group members are not sent to the AI.
- **On-device OCR:** the photo is processed on the phone by ML Kit.
- Manual entry is always available, so no one has to use the AI feature to use the app.

## 10. Tests

`flutter test` includes tests for this feature in `test/receipt_ai_test.dart` and `test/receipt_parser_test.dart`:
- JSON parsing converts pesos to centavos and rejects non-object answers.
- `redactForAi` masks card and phone numbers and emails and keeps prices.
- `reviewAiReceipt` flags unsure items, adds service charge and VAT, warns on a total mismatch, explains a discount, and returns null for unusable answers.
- Fallback chain: AI used when it works (with masked text), basic detection when the AI fails, one retry on a fast failure, fallback on timeout and on an unusable answer, a clear failure when nothing is found, and stage reporting.
- Screens: Scanning leads to Assign Items showing the AI label and **Needs review**; the Scanning error state shows Retake and Enter manually.
- Parser: prices become cents, totals are ignored, and dates, receipt numbers and other non-price numbers are skipped.

## 11. Items to complete yourself

- Add real **screenshots** (scan, scanning/loading, error with fallback, Assign Items with AI-detected and Needs review).
- Replace the sample in section 4 with a real receipt from your device.
- Record your own AI use in the **AI Usage Log** (generated code, debugging, sample data). Individual reflections must be written by you, not by AI.
