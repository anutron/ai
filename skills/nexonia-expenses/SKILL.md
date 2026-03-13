---
name: nexonia-expenses
description: Create, populate, and submit expense reports in Nexonia via browser automation. Reads pre-gathered expense materials from a folder, builds receipt-aligned line items, and automates form entry and receipt linking.
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion, ToolSearch, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__find, mcp__claude-in-chrome__form_input, mcp__claude-in-chrome__javascript_tool, mcp__claude-in-chrome__get_page_text, mcp__claude_ai_Gmail__gmail_search_messages, mcp__claude_ai_Gmail__gmail_read_message, mcp__claude_ai_Gmail__gmail_read_thread, mcp__google-calendar__list_events, mcp__google-calendar__search_events
---

# Nexonia Expense Report Skill

You help Aaron create and submit expense reports in Nexonia (Emburse). There are two main workflows:

- **Folder-based**: Aaron pre-gathers all expense materials (CSVs, receipt images, PDFs) into a folder. You read that folder, build receipt-aligned line items, automate form entry, and link receipts.
- **Receipt Wallet**: Aaron emails receipts to `receipts@nexonia.com` which puts them in Nexonia's Receipt Wallet. You read the wallet contents, create the report and line items, then move and link the wallet receipts.

## Nexonia URL

`https://b.na2.system.nexonia.com/assistant/expense/showExpense.do`

## Workflow Overview

### Workflow A: Folder-Based (Full)

1. **Discover expense folder** in `~/Downloads/`
2. **Ask what the report is for** — trip, monthly, one-off
3. **Inventory and parse** all materials in the folder + supplement from Gmail/Calendar
4. **Build receipt-aligned line items** — one receipt file = one line item
5. **Rename receipt files** for clarity (e.g., `le_colonial_2-12-26.png`)
6. **Categorize and present** the complete list for Aaron's approval
7. **Create report and enter line items** in Nexonia via browser automation
8. **Upload and link receipts** to line items
9. **Review and submit** after Aaron confirms

### Workflow B: Receipt Wallet (Lightweight)

1. **Open Receipt Wallet** in Nexonia and read the receipt contents
2. **Extract details** — vendor, amount, date, item description from the receipt images
3. **Ask Aaron** for category and any context needed
4. **Create report and enter line items** in Nexonia
5. **Move wallet receipts to report** (select all → move icon → pick report)
6. **Link receipts to items** inside each item edit
7. **Review and submit** after Aaron confirms

---

## Phase 1: Discover Expense Folder

Aaron gathers all expense materials into a single folder before invoking this skill.

### Discovery Steps

1. **Scan `~/Downloads/`** for directories modified in the last 30 days:
   ```bash
   find ~/Downloads -maxdepth 1 -type d -mtime -30 -not -name "." -not -name "Downloads" | sort -r
   ```
2. **For each candidate directory**, check if it contains expense-like files (CSVs, images, PDFs):
   ```bash
   find "$dir" -maxdepth 1 \( -name "*.csv" -o -name "*.pdf" -o -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.heic" \) | wc -l
   ```
3. **Pick the most recent match** and announce:
   > "I found your expense materials in `~/Downloads/<folder-name>/`. It contains: 3 CSVs, 5 images, 2 PDFs. Interrupt me if this is the wrong folder."
4. **Proceed unless Aaron interrupts.**

### Fallbacks

- **No matching folder**: Ask Aaron to specify a path
- **Multiple plausible folders**: List top 2-3 with file counts, ask which one
- **Empty or irrelevant folder**: Ask Aaron to confirm or provide the right path

---

## Phase 2: Understand Report Context

Ask Aaron what this expense report is for. This drives date filtering, department defaults, and report naming.

### Question Flow

Use `AskUserQuestion` — one question at a time:

1. **"What is this report for?"**
   - Options: A business trip / Monthly recurring expenses / A one-off expense

2. **If trip**: "Tell me about the trip — where and roughly when?"
   - Aaron will say something like "my trip to Atlanta a week or so ago"
   - Use **Google Calendar** (`search_events`) to find events in that city/timeframe and pin down exact dates
   - Use **Gmail** (`gmail_search_messages`) to find flight confirmations or hotel bookings that confirm the date range
   - Establish a **date range** for filtering CSV transactions

3. **If monthly**: "Which month?" — establishes the date range

4. **Suggest a department** based on context:
   - Customer visit → `501--General & Administration`
   - Conference/internal travel → `306--R&D Other`
   - Sales meeting → `101--Sales`
   - If unsure, ask Aaron

5. **Suggest a report name** using naming conventions (see Reference Data below)

---

## Phase 3: Inventory and Parse Materials

Read everything in the expense folder and build a raw data picture.

### Step 1: Read All Files in the Folder

- **CSVs**: Read and parse all CSV files. Identify which format they are:
  - Apple Card: `Transaction Date, Clearing Date, Description, Merchant, Category, Type, Amount (USD), Purchased By`
  - Bank download: `Date, Description, Original Description, Category, Amount, Status`
- **Images** (PNG, JPG, JPEG, HEIC): Use the Read tool to view each image (it's multimodal). Note what each receipt is for — vendor, amount, date.
- **PDFs**: Use the Read tool with `pages` parameter. Note vendor, amount, date from each.

### Step 2: Filter CSV Transactions

Using the date range from Phase 2:

- **Include** transactions within the trip date range (± 1 day for travel days)
- **Exclude personal**: Grocery stores (Trader Joe's), personal purchases, payments/credits
- **Rebecca's purchases**: Check `Purchased By` column — Rebecca Newton's items are usually personal
- **Lyft on travel days**: Include rides to/from airports even if in home city (SFO)

### Step 3: Supplement from Gmail/Calendar

Search for receipts that may not be in the folder:

```
# Flight confirmations
from:deltaairlines OR from:united OR from:southwest subject:confirmation after:YYYY/MM/DD

# Hotel folios
subject:folio OR subject:"hotel receipt" after:YYYY/MM/DD

# Xfinity/Comcast bill (search for "Xfinity" not "Comcast")
from:xfinity OR from:comcast subject:bill
```

**Important**: Gmail MCP is connected to **work email** (aaron@thanx.com). For personal email (anutron@gmail.com), you need Chrome browser automation.

Flag any email-sourced receipts that aren't already in the folder — Aaron may need to save them to the folder before proceeding.

---

## Phase 4: Build Receipt-Aligned Line Items

**Core principle: one receipt file = one line item in Nexonia.**

Every line item must have exactly one receipt that proves the charge. Don't split expenses beyond what a single receipt can support.

### How to Build the Mapping

1. **Start from receipt files** (not CSV transactions). For each receipt file in the folder:
   - What vendor is it from?
   - What total amount does it show?
   - What date(s) does it cover?

2. **Match CSV transactions to receipts.** For each receipt:
   - Find the corresponding CSV row(s)
   - If a receipt covers multiple CSV rows (e.g., a Lyft PDF covering 5 rides), **sum those rows into a single line item**
   - Use the receipt's total as the line item amount

3. **Handle special cases:**
   - **Lyft**: A single Lyft PDF/summary covering all rides during a trip = ONE line item with the total. Memo: "Rideshare during [City] trip, X rides"
   - **Hotel**: A hotel folio covering multiple nights = ONE line item with the total
   - **Multiple charges at same vendor**: If one receipt covers them, one line item. If separate receipts, separate line items.

4. **Flag gaps:**
   - CSV transactions with no matching receipt → Tell Aaron: "I see a $95.78 charge at Velvet Taco on 2/17 but no receipt for it. Do you have one to add to the folder?"
   - Receipt files that don't match any CSV transaction → Ask Aaron to clarify

### Line Item Data Model

For each line item, track:
- `receipt_file` — The receipt file path (1:1 relationship)
- `vendor` — Vendor name for SERVICE_PROVIDER field
- `date` — Transaction date (MM/DD/YYYY), prefer receipt date over CSV posting date
- `amount` — Total from the receipt
- `category_parent` — e.g., "Travel & Entertainment"
- `category_sub` — e.g., "Ground Transportation"
- `department` — e.g., "306--R&D Other"
- `memo` — Optional context
- `source_transactions` — Which CSV rows are covered (for reference)

---

## Phase 5: Rename Receipt Files

Rename all receipt files in the folder to clearly identify which receipt matches which expense.

### Naming Pattern

`vendor_M-DD-YY.ext`

**Examples:**
- `le_colonial_2-12-26.png`
- `hyatt_2-15-26.pdf`
- `delta_2-11-26.pdf`
- `lyft_2-12-to-2-15-26.pdf` (multi-day receipt)
- `xfinity_2-01-26.pdf`
- `linkedin_2-15-26.png`

**Rules:**
- Snake_case for vendor names (lowercase, underscores for spaces)
- Date format: `M-DD-YY` (no leading zero on month)
- Multi-day receipts: `M-DD-to-M-DD-YY`
- Use `mv` (not `cp`) to avoid duplicates

Rename via Bash:
```bash
mv ~/Downloads/expense-folder/IMG_1234.png ~/Downloads/expense-folder/le_colonial_2-12-26.png
```

---

## Phase 6: Categorize and Present for Approval

Present the complete receipt-aligned line item list to Aaron for approval before entering anything in Nexonia.

### Presentation Format

Show a table with all line items:

```
| # | Receipt File | Vendor | Date | Amount | Category | Department | Memo |
|---|---|---|---|---|---|---|---|
| 1 | delta_2-11-26.pdf | Delta Airlines | 02/11/2026 | $487.00 | T&E >> Airfare | 306--R&D Other | |
| 2 | hyatt_2-12-to-2-14-26.pdf | Hyatt Regency | 02/12/2026 | $568.32 | T&E >> Lodging | 306--R&D Other | |
| 3 | lyft_2-11-to-2-14-26.pdf | Lyft | 02/11/2026 | $310.66 | T&E >> Ground Transportation | 306--R&D Other | 8 rides, airport + meetings |
| 4 | le_colonial_2-12-26.png | Le Colonial | 02/12/2026 | $128.45 | T&E >> Meals | 306--R&D Other | Team dinner |
| 5 | ritual_2-13-26.png | Ritual Coffee | 02/13/2026 | $12.50 | T&E >> Expense - Per Diem | 306--R&D Other | |
```

**Total: $1,506.93**

### Questions to Resolve

- Any items to add or remove?
- Any category or department corrections?
- Confirm report name
- Any meal categorization questions (team vs solo)?

**Do not proceed to browser automation until Aaron approves.**

---

## Phase 7: Reference Data

### Constants (Always the Same)

These fields are ALWAYS set to these values:
- **Customer**: `Sample Customer`
- **Project**: `Sample Project`
- **Location**: `400--Thanx, Inc.`
- **Paid By**: `Employee`
- **Reimburse**: `Yes`

### Category Mapping

Categories are hierarchical: `Parent >> Subcategory`

| Expense Type | Category Parent | Category Sub | Examples |
|---|---|---|---|
| Flights | Travel & Entertainment | Airfare | United, Delta, Southwest flights |
| In-flight wifi | Travel & Entertainment | Airfare | United Wifi ($8) |
| Hotels | Travel & Entertainment | Lodging | Hyatt, Marriott, Airbnb, Element |
| Uber/Lyft/taxi/parking | Travel & Entertainment | Ground Transportation | Lyft, Waymo, parking garages |
| Meals (solo, travel) | Travel & Entertainment | Expense - Per Diem | Coffee, solo meals while traveling |
| Meals (team/client) | Travel & Entertainment | Meals | Team dinners, client meals |
| Internet (Comcast/Xfinity) | Administration/Other | Office & Kitchen Supplies | Monthly Xfinity bill |
| Office equipment/furniture | Administration/Other | Office & Kitchen Supplies | Monitors, desks, construction |
| Computer hardware | IT/Systems | Computer Hardware & Software Expenses | MacBook, monitors, peripherals |
| SaaS subscriptions | IT/Systems | SAAS Expenses | LinkedIn ($69.99), Superhuman ($30) |

#### Meal Categorization Rules

- **Team meals** (2+ Thanx employees eating together) → `Travel & Entertainment >> Meals`
- **Client/customer meals** (with external guests) → `Travel & Entertainment >> Meals`
- **Solo travel meals** (eating alone during trip) → `Travel & Entertainment >> Expense - Per Diem`
- **Coffee at airport** → `Travel & Entertainment >> Expense - Per Diem`

### Department Mapping

| Purpose | Department Code |
|---|---|
| R&D work, conferences, general travel | `306--R&D Other` |
| Customer onsites, client meetings | `501--General & Administration` |
| Sales meetings, prospect visits | `101--Sales` |
| Monthly recurring (internet, SaaS) | `306--R&D Other` |
| Office equipment/supplies | `306--R&D Other` |

**Key insight**: Default to `501--General & Administration` for customer-facing trips, `306--R&D Other` for internal/conference travel. When unsure, ask Aaron.

### Report Naming Conventions

- **Trip-based**: `[City] - [Month] [Year]` (e.g., "Atlanta - Feb 2026")
- **Trip + event**: `[City] - [Event] [Month]` (e.g., "Boston - M33 Nov")
- **Monthly bundle**: `[Month] expenses` or `[Month] [Year] expenses`
- **Single purpose**: `[Description]` (e.g., "Parking for sales")
- **Recurring**: `[Month] internet` for standalone internet expenses

### Memo Field Guidelines

- **Airfare**: Include trip destination if not obvious from report title
- **Ground transport**: Summarize (e.g., "8 rides, airport + meetings during Atlanta trip")
- **Team/client meals**: Note context (e.g., "Team dinner", "Customer dinner with [client]")
- **SaaS**: Include the product name (e.g., "Linkedin Premium Business")
- **Office supplies**: Describe what was purchased
- **Leave blank** when the report title already provides context

---

## Phase 8: Browser Automation — Create Report and Enter Line Items

### Prerequisites

Before starting browser automation:
1. Load Chrome tools via `ToolSearch` (e.g., `select:mcp__claude-in-chrome__tabs_context_mcp`)
2. Call `tabs_context_mcp` to get current browser state
3. Create a new tab or navigate existing one to Nexonia

### Create New Report

1. Navigate to `https://b.na2.system.nexonia.com/assistant/expense/showExpense.do`
2. Click **"Add Report"**
3. Use `read_page` to find the Title input field ref
4. Use `form_input` to type the report title (don't use `computer` type action for text fields)
5. Click Save

### Add Expense Items — Detailed Form Steps

For each line item from the approved list:

1. **Click "Add Expense Item"** (green button) — use `find` to locate it
2. **Wait for form to load**, then use `read_page` to get field refs

3. **Category Parent** (dropdown, typically `ref_169`):
   - Use `form_input` with `ref` and `value` to select (e.g., `"Travel & Entertainment"`)

4. **Category Sub** (dropdown, typically `ref_188`):
   - Use `form_input` to select subcategory (e.g., `"Airfare"`)

5. **Transaction Date** (text field, typically `ref_170`):
   - Use `form_input` to enter date in `MM/DD/YYYY` format

6. **Total** (text field, typically `ref_173`):
   - Use `form_input` to enter the dollar amount (no $ sign)

7. **Department** (dropdown):
   - Use `find` to locate Department dropdown, then `form_input` to select

8. **Location** (dropdown):
   - Should already default to `400--Thanx, Inc.`, verify and set if needed

9. **SERVICE_PROVIDER** (text field):
   - **CRITICAL**: The ref for this field **changes after every save**. Always use `find` with query like `"SERVICE_PROVIDER text input"` to get the current ref before each entry
   - Use `form_input` to type the vendor name

10. **Memo** (text field, typically `ref_180`):
    - Use `form_input` if memo is needed, skip if blank

11. **Save**:
    - Click **"Save and New"** (`ref_185`) for all items except the last
    - Click **"Save and Close"** (`ref_187`) for the last item

### Critical Automation Notes

- **Ref IDs may vary between sessions** — always use `find` or `read_page` to confirm refs before interacting
- **SERVICE_PROVIDER ref changes every save** — must re-find it each time
- **Use `form_input` for all text/dropdown fields** — `computer` type action is unreliable for text entry
- **Use `find` to locate elements** when refs aren't working or have changed
- **After all items entered**, take a screenshot to verify the subtotal matches expected total

### Date Handling

- Use the **transaction date** from the receipt, not the bank posting date
- Bank CSV dates may be 1 day later than actual transaction (posting delay)
- When receipt shows different date than CSV, prefer the receipt date

---

## Phase 9: Receipt Linking

After all line items are entered, link each receipt to its corresponding line item. Receipts can come from two sources: the **Receipt Wallet** (emailed to `receipts@nexonia.com`) or **bulk upload** from a folder.

### Receipt Source A: Receipt Wallet (Email)

If Aaron emailed receipts to `receipts@nexonia.com`, they land in the **Receipt Wallet**.

**Step 1: Move receipts from wallet to report**

1. From the main expenses list, click **"Receipt Wallet"** button
2. Click the **select-all checkbox** (top-left, next to "Add Receipts")
3. Click the **arrow/move icon** (→✓) that appears in the toolbar
4. A "Select report" dialog appears — choose the target report from the dropdown
5. Click **"Move"**
6. The wallet empties — receipts are now attached to the report

**Step 2: Link receipts to line items**

1. Open the report: click **Action > Edit** on the report row
2. For each line item that needs receipts linked:
   a. Click **Action > Edit** on the line item row
   b. In the item edit dialog, click **"Not linked (N)"** tab in the center column
   c. The unlinked receipt thumbnails appear in the center column
   d. Click a thumbnail to preview it on the right
   e. Find the receipt that matches this line item
   f. Click the **green chain-link icon** (🔗) above the preview image on the right
   g. The receipt moves from "Not linked" to "Linked"
   h. **Repeat for each receipt page** that belongs to this item (link one at a time)
3. Click **"Save and Close"**

**Important**: Each receipt must be linked individually — you cannot bulk-link. But one item can have multiple linked receipts (e.g., a multi-page email receipt).

### Receipt Source B: Bulk Upload from Folder

If Aaron has receipt files in a local folder:

1. Open the report, click **"Manage Receipts (N)"**
2. Click **"Add Receipts" > "Upload"**
3. Aaron drags/drops all files from `~/Downloads/<folder-name>/`
4. After upload completes, follow **Step 2** above to link each receipt to its item

### Verify Linkage

After linking, verify:
- Each line item shows a **green paperclip icon** (not red/orange alert)
- **"Manage Receipts (N)"** count matches total uploaded
- The **Count column** on the main list shows linked status (e.g., "1/3" = 1 item, 3 receipts)

---

## Phase 10: Review and Submit

1. **Show Aaron the completed report summary** — all items, amounts, categories, receipt status
2. **Verify subtotal** matches the sum of all items
3. **Verify receipt count** — all items should show receipts linked
4. **Confirm** everything looks correct
5. **Only submit after Aaron explicitly confirms** — never auto-submit
6. Click **"Submit"** button on the report

---

## Common Expense Patterns

### Business Trip (most common)

Typical line items for a trip report (each backed by one receipt):
1. Airfare (round trip — one flight confirmation)
2. Lodging (hotel folio — one PDF, total including taxes)
3. Ground transportation (Lyft — one PDF/summary covering all rides during the trip)
4. In-flight wifi (if separate receipt exists; otherwise include in airfare memo)
5. Meals (one receipt per restaurant visit)
6. Coffee/snacks (one receipt each)

### Monthly Recurring

1. Comcast/Xfinity internet — Admin/Other >> Office & Kitchen Supplies
2. LinkedIn Premium ($69.99) — IT/Systems >> SAAS Expenses
3. Other SaaS subscriptions

### One-off Expenses

- Parking for meetings
- Team lunches
- Office equipment purchases

---

## Aaron's Payment Methods

Aaron uses multiple cards — a single trip's expenses will span multiple cards/statements:

| Card | CSV Source | Typical Charges |
|---|---|---|
| Apple Card (MasterCard *5646) | `Apple Card Transactions*.csv` | Lyft, restaurants, coffee, small purchases |
| Visa ****2436 | `bk_download.csv` or bank app | Hotels, large restaurant bills, flights |
| Other cards | Various | Check with Aaron |

### CSV Formats

**Apple Card CSV columns:**
`Transaction Date, Clearing Date, Description, Merchant, Category, Type, Amount (USD), Purchased By`

**Bank download CSV columns:**
`Date, Description, Original Description, Category, Amount, Status`

### Filtering Tips

- **Trip expenses**: Match by location (city/state) and date range
- **Exclude personal**: Grocery stores (Trader Joe's), personal purchases, payments/credits
- **Rebecca's purchases**: Check `Purchased By` column — Rebecca Newton's items are usually personal (groceries)
- **Lyft rides on travel days**: Include rides to/from airports even if in home city (SFO)
- **Comcast/Xfinity**: Search email for "Xfinity" not "Comcast" — the brand name changed

### Gmail Search Patterns

```
# Flight confirmations
from:deltaairlines OR from:united OR from:southwest subject:confirmation after:YYYY/MM/DD

# Hotel folios
subject:folio OR subject:"hotel receipt" after:YYYY/MM/DD

# Xfinity/Comcast bill
from:xfinity OR from:comcast subject:bill
```

**Important**: Gmail MCP is connected to **work email** (aaron@thanx.com). For personal email (anutron@gmail.com), you need Chrome browser automation.

---

## Important Notes

- **One receipt = one line item** — never split an expense beyond what a single receipt proves
- **Always confirm before submitting** — never auto-submit without Aaron's approval
- **Rename receipt files first** — clear filenames make bulk upload + linking possible
- **Department uncertainty**: When unsure, ask Aaron
- **All dates in MM/DD/YYYY format** in the Nexonia UI
- **The "Count" column** (e.g., "4/6") shows items with receipts vs total items
- **Chrome extension must be connected** for browser automation
- **Gmail MCP** is work email only (aaron@thanx.com) — personal email needs Chrome browser
