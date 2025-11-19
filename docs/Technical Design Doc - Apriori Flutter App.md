# Technical Design Document: "BasketTech" Recommendation App

## 1. Project Overview

**Goal:** Create a Flutter-based concept application that demonstrates the Apriori algorithm for on-device product recommendations.

**Core Concept:**
The app functions as both a Point of Sale (POS) and a shopping interface. It tracks transactions and uses historical purchase data to generate association rules (e.g., "People who buy Bread also buy Butter") to recommend products during browsing and checkout.

**Tech Stack:**
- **Framework:** Flutter (Dart)
- **Database:** SQFlite (Local, on-device storage)
- **State Management:** Provider or Riverpod (Recommended for cart/product state)
- **Processing:** In-app synchronous/isolate-based calculation (No backend)

---

## 2. Functional Requirements

### A. Product Management (Merchant View)
- **Product List:** View all available items.
- **CRUD Operations:**
  - **Create:** Add new product (Name, Price, Image URL/Icon, Category).
  - **Update:** Edit details.
  - **Delete:** Remove product (Soft delete recommended to preserve historical transaction integrity).

### B. Shopping & Transactions (User View)
- **Product Page:** Detailed view of a specific item.
  - **Feature:** Contextual Recommendations. (Logic: Display items that appear in Association Rules where the current item is the Antecedent).
- **Cart System:** Ability to add multiple items to a temporary list.
- **Checkout Page:**
  - List of items in the current cart.
  - **Feature:** Cart-Based Recommendations. (Logic: Apriori analysis of the set of items currently in the cart).
  - **Complete Transaction:** Saves the cart as a permanent Transaction Record and clears the cart.

### C. History & Analytics
- **Transaction List:** View history of completed orders (Order ID, Date, Items, Total Price).
- **Rule Visualization (Optional):** A debug page showing the generated Apriori rules (e.g., `{Diapers} -> {Beer} [Confidence: 80%]`).

---

## 3. Database Schema (SQFlite)

We need three primary tables and one derived table for the rules.

### Table 1: `products`
| Field      | Type    | Description                |
|------------|---------|----------------------------|
| id         | INTEGER | Primary Key, Auto-increment|
| name       | TEXT    | Product Name               |
| price      | REAL    | Unit Price                 |
| image_path | TEXT    | Local path or asset ID     |

### Table 2: `transactions`
| Field       | Type    | Description                |
|-------------|---------|----------------------------|
| id          | INTEGER | Primary Key (Transaction ID)|
| timestamp   | INTEGER | Unix Epoch time            |
| total_amount| REAL    | Final cost                 |

### Table 3: `transaction_items` (Junction Table)
| Field          | Type    | Description                      |
|----------------|---------|----------------------------------|
| id             | INTEGER | Primary Key                      |
| transaction_id | INTEGER | Foreign Key -> transactions.id   |
| product_id     | INTEGER | Foreign Key -> products.id       |

### Table 4: `association_rules` (Cached Results)
Calculated by Apriori, stored for fast lookup.

| Field      | Type    | Description                                         |
|:-----------|:--------|:---------------------------------------------------|
| id         | INTEGER | Primary Key                                        |
| antecedent | TEXT    | JSON string of input IDs: `[1, 4]` (If buy 1 & 4...)|
| consequent | TEXT    | JSON string of output IDs: `[7]` (...then buy 7)   |
| confidence | REAL    | Probability (0.0 to 1.0)                           |
| support    | REAL    | Frequency (0.0 to 1.0)                             |
| lift       | REAL    | Strength of association                            |

---

## 4. Apriori Algorithm Implementation Strategy

Since this is running on a mobile device, we must balance accuracy with performance.

### Phase 1: Data Preparation
1. Fetch all `transaction_items` grouped by `transaction_id`.
2. Convert to a List of Sets: `List<Set<int>> dataset`.
	- Example:
	  ```dart
	  [{1, 2, 3}, {1, 2}, {2, 3, 4}]
	  ```

### Phase 2: The Algorithm Logic (Dart)
You can use a simplified Apriori approach:
1. **Calculate Support:**
	- Count occurrences of every individual item.
	- Filter items below `min_support` (e.g., must appear in at least 10% of transactions).
2. **Generate Pairs (Itemsets of size 2):**
	- Create combinations of frequent items.
	- Count occurrences of these pairs in the transactions.
	- Filter by `min_support`.
3. **Generate Rules:**
	- For every frequent set `{A, B}`, calculate Confidence for rules:
	  - `{A} -> {B}`: $\\text{Confidence} = \\frac{\\text{Support}({A,B})}{\\text{Support}({A})}$
	  - `{B} -> {A}`: $\\text{Confidence} = \\frac{\\text{Support}({A,B})}{\\text{Support}({B})}$
	- Keep rules where Confidence > `min_confidence` (e.g., 50%).

### Phase 3: Execution Trigger
**Crucial Concept:** Do not run Apriori live when the user opens a page. It is $O(2^N)$ complexity.
- **Trigger:** Run the calculation asynchronously immediately after a transaction is completed (checkout).
- **Storage:** Save the resulting high-confidence rules into the `association_rules` table.

---

## 5. Recommendation Logic (The "Smart" Part)

### Scenario A: Product Page (Context: Single Item ID X)
1. Query `association_rules` table.
2. Filter where antecedent contains exactly `[X]`.
3. Sort by confidence DESC.
4. Display top 3 items from consequent.

### Scenario B: Checkout Page (Context: List of IDs `[X, Y, Z]`)
This is more complex. You have three strategies:
1. **Exact Match (High Precision):** Look for a rule where antecedent is exactly `[X, Y, Z]`. (Rare).
2. **Subset Match (Medium Precision):** Look for rules where antecedent is a subset, e.g., `[X, Y] -> ?`.
3. **Best Single Match (Fallback):** Iterate through items in cart.
	- Get recommendations for X.
	- Get recommendations for Y.
	- Get recommendations for Z.
	- Merge lists, remove duplicates (and remove items already in cart).
	- Sort by highest confidence.

---

## 6. Implementation Roadmap

**Step 1: Scaffold & Database (Days 1-2)**
- Set up Flutter project.
- Create `DatabaseHelper` class using sqflite.
- Implement methods: `insertProduct`, `getAllProducts`, `insertTransaction`.

**Step 2: UI - Product Management (Day 3)**
- Build "Inventory" screen (`ListView` of products).
- Build "Add Product" form.

**Step 3: Shopping Flow (Day 4)**
- Build "Shop" screen (Grid of products).
- Build "Product Detail" screen.
- Build "Cart" logic (using `ChangeNotifier` provider).
- Build "Checkout" screen (List of items + "Pay" button).

**Step 4: The Algorithm (Day 5-6)**
- Create `AprioriService` class.
- Implement `generateRules(List<Transaction> history)` method.
- Tip: Start with pre-defined data to test logic before hooking up the UI.

**Step 5: Integration (Day 7)**
- Connect "Product Detail" page to `AprioriService` to show "Frequently bought with this".
- Connect "Checkout" page to suggest "You might be forgetting...".

---

## 7. Edge Cases & Limitations

1. **Cold Start:** The app starts with 0 transactions. No recommendations will appear.
	- *Solution:* Add a "Seed Database" button in settings that injects 50 mock transactions.
2. **Performance:** If transactions > 10,000, pure Dart calculation on the UI thread will freeze the app.
	- *Solution:* Use `Flutter compute()` to run Apriori in a background isolate.
