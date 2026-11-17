# CP1 — Normalization Analysis

## CampusLens Database Schema — 1NF / 2NF / 3NF

---

## Overview

The CampusLens schema comprises seven tables: `colleges`, `college_email_domains`, `profiles`, `events`, `photos`, `tags`, and `photo_tags`. This document analyses each table against First, Second, and Third Normal Form (1NF, 2NF, 3NF) and justifies three intentional deviations from strict 3NF.

---

## 1. First Normal Form (1NF)

**Definition:** Every column contains only atomic (indivisible) values; no repeating groups; every row is uniquely identifiable.

| Table | 1NF Status | Notes |
|---|---|---|
| `colleges` | ✅ Satisfies 1NF | All columns atomic; UUID PK |
| `college_email_domains` | ✅ Satisfies 1NF | One domain per row; UUID PK |
| `profiles` | ✅ Satisfies 1NF | All columns atomic; UUID PK |
| `events` | ✅ Satisfies 1NF | All columns atomic; UUID PK |
| `photos` | ⚠️ Controlled deviation | `hashtags TEXT[]` is a multivalued column — see §5.1 |
| `tags` | ✅ Satisfies 1NF | All columns atomic; UUID PK |
| `photo_tags` | ✅ Satisfies 1NF | Bridge table; two FKs + PK |

---

## 2. Second Normal Form (2NF)

**Definition:** Satisfies 1NF and every non-key attribute is fully functionally dependent on the whole primary key (no partial dependencies).

All seven tables use a single-column UUID primary key. Because the PK is never composite, partial dependency is structurally impossible — 2NF is trivially satisfied for every table.

| Table | 2NF Status | Reason |
|---|---|---|
| `colleges` | ✅ Satisfies 2NF | Single-column PK — no partial dependency possible |
| `college_email_domains` | ✅ Satisfies 2NF | Single-column PK |
| `profiles` | ✅ Satisfies 2NF | Single-column PK |
| `events` | ✅ Satisfies 2NF | Single-column PK |
| `photos` | ✅ Satisfies 2NF | Single-column PK |
| `tags` | ✅ Satisfies 2NF | Single-column PK; `UNIQUE(college_id, name)` is a candidate key but not the PK |
| `photo_tags` | ✅ Satisfies 2NF | Single-column PK; `UNIQUE(photo_id, tag_id)` is a candidate key |

---

## 3. Third Normal Form (3NF)

**Definition:** Satisfies 2NF and no non-key attribute is transitively dependent on the primary key through another non-key attribute.

### 3.1 `colleges`

| Column | Depends on | Transitive? |
|---|---|---|
| `name`, `short_name`, `city`, `is_active`, `created_at` | `id` (PK) directly | No |

✅ Satisfies 3NF.

### 3.2 `college_email_domains`

| Column | Depends on | Transitive? |
|---|---|---|
| `college_id`, `domain`, `created_at` | `id` (PK) directly | No |

✅ Satisfies 3NF. `domain` → `college_id` could be read as a dependency, but since `domain` itself is a non-key attribute (not the determinant of other non-keys), there is no transitive dependency.

### 3.3 `profiles`

| Column | Depends on | Transitive? |
|---|---|---|
| `user_id`, `college_id`, `full_name`, `batch_year`, `is_onboarding_complete`, `created_at`, `updated_at` | `id` (PK) directly | No |

✅ Satisfies 3NF.

### 3.4 `events`

| Column | Depends on | Transitive? |
|---|---|---|
| `college_id`, `name`, `year`, `event_date`, `created_at` | `id` (PK) directly | No |

✅ Satisfies 3NF.

### 3.5 `photos`

| Column | Depends on | Transitive? |
|---|---|---|
| `uploader_id`, `event_id`, `caption`, `hashtags`, `cloudinary_public_id`, `image_url`, `thumbnail_url`, `year`, `is_approved`, `uploaded_at`, `created_at`, `updated_at` | `id` (PK) directly | No |
| `college_id` | `id` (PK) directly — **controlled deviation** | Technically transitive via `uploader_id → profiles.college_id`; see §5.2 |

⚠️ One controlled deviation — see §5.2. Otherwise satisfies 3NF.

### 3.6 `tags`

| Column | Depends on | Transitive? |
|---|---|---|
| `college_id`, `name`, `created_at` | `id` (PK) directly | No |
| `usage_count` | `id` (PK) directly — **controlled deviation** | Derivable by counting `photo_tags` rows; see §5.3 |

⚠️ One controlled deviation — see §5.3. Otherwise satisfies 3NF.

### 3.7 `photo_tags`

| Column | Depends on | Transitive? |
|---|---|---|
| `photo_id`, `tag_id`, `created_at` | `id` (PK) directly | No |

✅ Satisfies 3NF.

---

## 4. Summary Table

| Table | 1NF | 2NF | 3NF | Notes |
|---|---|---|---|---|
| `colleges` | ✅ | ✅ | ✅ | Fully normalized |
| `college_email_domains` | ✅ | ✅ | ✅ | Fully normalized |
| `profiles` | ✅ | ✅ | ✅ | Fully normalized |
| `events` | ✅ | ✅ | ✅ | Fully normalized |
| `photos` | ⚠️ | ✅ | ⚠️ | Two controlled deviations (§5.1, §5.2) |
| `tags` | ✅ | ✅ | ⚠️ | One controlled deviation (§5.3) |
| `photo_tags` | ✅ | ✅ | ✅ | Fully normalized |

**Conclusion:** The schema is in Third Normal Form. Three documented deviations exist, each justified by a specific performance or correctness requirement.

---

## 5. Justified Deviations

### 5.1 `photos.hashtags TEXT[]` — Controlled 1NF Deviation

**Violation:** A PostgreSQL `TEXT[]` column stores multiple tag strings in a single row, which violates strict 1NF atomicity.

**Justification:**

- The normalized counterpart already exists: `tags` and `photo_tags` store the same information in proper relational form.
- `hashtags TEXT[]` exists solely to enable fast array-containment search using PostgreSQL's GIN (Generalized Inverted Index): `WHERE hashtags @> ARRAY['Damru26']`. A GIN index on a text array can answer this query with a single Bitmap Index Scan, avoiding a multi-table join through `photo_tags` and `tags`.
- PostgreSQL treats a `TEXT[]` value as an atomic column value at the SQL level (it has a defined type, operators, and index support), so it does not introduce the update anomalies that classical repeating groups do.
- The two representations are kept in sync at application write time (`lib/hashtags.ts` populates both on every upload).

**Trade-off:** `hashtags` can drift from `photo_tags` if a tag row is deleted without updating the array. This risk is accepted because tag deletes are not part of the application flow.

### 5.2 `photos.college_id` — Controlled 3NF Deviation

**Violation:** `photos.college_id` is transitively dependent on `photos.id` through `photos.uploader_id → profiles.college_id`. Strictly, `college_id` on a photo row is derivable by joining to `profiles`.

**Justification:**

- CampusLens is a **multi-tenant** application. Every Row Level Security policy on `photos` must filter by college to prevent cross-college data leakage. Without `photos.college_id`, every policy check would require a subquery join through `profiles`:
  ```sql
  -- Without denormalization (expensive):
  USING (college_id IN (SELECT college_id FROM profiles WHERE user_id = auth.uid()))
  -- requires joining photos → profiles on every row check
  ```
- With `photos.college_id` present and indexed (`idx_photos_college`), the gallery load query `WHERE college_id = $1` hits a plain B-tree index scan and returns only the caller's college rows before any further filtering. This is the single most performance-critical query in the application (up to 200 rows loaded at every session start).
- The column is populated at INSERT time from the authenticated user's profile and cannot be changed thereafter (no UPDATE policy on `photos`).

**Trade-off:** If a college row were deleted and `ON DELETE CASCADE` did not exist, orphaned `photos` rows could have a stale `college_id`. The CASCADE constraint closes this gap.

### 5.3 `tags.usage_count` — Derived-Attribute Denormalization

**Violation:** `usage_count` is a derived attribute — its true value is `SELECT COUNT(*) FROM photo_tags WHERE tag_id = tags.id`. Storing a derived value violates strict 3NF (the value is functionally determined by the state of another table, not solely by `tags.id`).

**Justification:**

- The gallery UI displays a "Popular Tags" panel sorted by `usage_count DESC`. Computing a live `COUNT(*)` aggregation over `photo_tags` on every gallery load — with up to 200 photos each having multiple tags — would require a full aggregation scan at read time.
- Maintaining `usage_count` as an incrementable integer (`UPDATE tags SET usage_count = usage_count + 1 WHERE id = $1`) makes the popular-tags query a simple `ORDER BY usage_count DESC LIMIT 20` on the indexed column `idx_tags_usage`, resolving in a single Index Scan.
- The counter is incremented in `lib/hashtags.ts` at upload time, immediately after the `photo_tags` row is inserted. The increment is not transactional with the insert, so brief inconsistency is possible under failure, but eventual consistency is acceptable for a display-only popularity metric.

**Trade-off:** `usage_count` is never decremented (the app has no tag-delete path), so it over-counts if photos are deleted. For the current application scope this is an accepted limitation.

---

## 6. Conclusion

The CampusLens schema is in **Third Normal Form**. All primary keys are single-column UUIDs, eliminating any possibility of partial dependency. No non-key column is transitively dependent on the PK through another non-key column, with three documented exceptions:

1. `photos.hashtags TEXT[]` — a 1NF deviation enabling GIN-accelerated hashtag search, with a normalized shadow in `photo_tags`.
2. `photos.college_id` — a 3NF deviation eliminating a join from every multi-tenant RLS policy check.
3. `tags.usage_count` — a derived-attribute denormalization enabling O(1) popular-tag lookup.

Each deviation is intentional, documented, and bounded in scope. The underlying relational structure remains clean and consistent.
