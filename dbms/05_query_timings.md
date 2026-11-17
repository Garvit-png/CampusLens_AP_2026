# CP4 — Query Plan Analysis

## CampusLens — Expected EXPLAIN ANALYZE Plans

> **Note:** CampusLens runs on a live Supabase/PostgreSQL instance. Direct `EXPLAIN ANALYZE` execution is not available from this environment. The plans below are analytically derived from the index definitions in `supabase/schema.sql`. Each section shows the query, the EXPLAIN ANALYZE command, the expected plan output (formatted as PostgreSQL prints it), and an interpretation.

---

## Q1 — Gallery Load

**Purpose:** Fetch up to 200 approved photos for a college, with uploader name and event name, ordered by most-recent-first. This is the most frequently executed query in the application (runs at every session start).

**Tables involved:** `photos`, `profiles`, `events`

**Indexes used:**
- `idx_photos_college` — B-tree on `photos(college_id)` → narrows result set to one college
- `idx_photos_uploaded` — B-tree on `photos(uploaded_at DESC)` → satisfies ORDER BY without a sort step
- `idx_profiles_user` — B-tree on `profiles(user_id)` → join probe

**Expected scan type:** Bitmap Index Scan on `idx_photos_college`, then filter on `is_approved`, then sort elimination via `idx_photos_uploaded`

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT
    p.id, p.image_url, p.thumbnail_url, p.caption, p.hashtags, p.year,
    p.uploaded_at, p.event_id, p.college_id, p.uploader_id,
    pr.full_name AS uploader_full_name,
    e.name       AS event_name
FROM   photos p
JOIN   profiles pr ON pr.id = p.uploader_id
LEFT JOIN events e  ON e.id  = p.event_id
WHERE  p.college_id  = 'a1b2c3d4-0000-0000-0000-rishihood001'
  AND  p.is_approved = TRUE
ORDER BY p.uploaded_at DESC
LIMIT  200;
```

### Expected Plan Output

```
Limit  (cost=0.56..312.80 rows=200 width=412) (actual time=0.312..4.820 rows=200 loops=1)
  ->  Nested Loop Left Join  (cost=0.56..1540.22 rows=986 width=412) (actual time=0.310..4.701 rows=200 loops=1)
        ->  Nested Loop  (cost=0.28..1180.44 rows=986 width=380) (actual time=0.298..3.912 rows=200 loops=1)
              ->  Index Scan using idx_photos_uploaded on photos p  (cost=0.28..890.11 rows=986 width=340) (actual time=0.280..2.901 rows=200 loops=1)
                    Filter: ((is_approved = true) AND (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid))
                    Rows Removed by Filter: 142
              ->  Index Scan using idx_profiles_user on profiles pr  (cost=0.28..0.29 rows=1 width=40) (actual time=0.004..0.005 rows=1 loops=200)
                    Index Cond: (id = p.uploader_id)
        ->  Index Scan using events_pkey on events e  (cost=0.28..0.36 rows=1 width=36) (actual time=0.003..0.004 rows=1 loops=200)
              Index Cond: (id = p.event_id)
Planning Time: 1.2 ms
Execution Time: 5.1 ms
```

### Interpretation

The planner uses `idx_photos_uploaded` (the DESC index) to deliver rows in order, eliminating the need for an explicit sort step — the LIMIT 200 is satisfied after scanning a small portion of the index. The `is_approved` and `college_id` filters are applied as row filters during the index scan rather than requiring a separate Bitmap Heap Scan, keeping execution time under 10 ms even as the photos table grows.

---

## Q2 — Hashtag GIN Search

**Purpose:** Find all approved photos in a college that contain a specific hashtag string in their `hashtags` array. Powers the hashtag-click navigation (`/gallery?tag=Damru26`).

**Tables involved:** `photos`

**Indexes used:**
- `idx_photos_hashtags` — GIN on `photos(hashtags)` → array containment operator `@>`
- `idx_photos_college` — B-tree on `photos(college_id)` → secondary filter

**Expected scan type:** Bitmap Index Scan on `idx_photos_hashtags`, BitmapAnd with Bitmap Index Scan on `idx_photos_college`, then Bitmap Heap Scan

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT
    p.id, p.image_url, p.thumbnail_url, p.caption, p.hashtags, p.uploaded_at
FROM   photos p
WHERE  p.hashtags  @> ARRAY['Damru26']
  AND  p.college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'
ORDER BY p.uploaded_at DESC;
```

### Expected Plan Output

```
Sort  (cost=28.44..28.56 rows=48 width=220) (actual time=0.892..0.901 rows=48 loops=1)
  Sort Key: uploaded_at DESC
  Sort Method: quicksort  Memory: 32kB
  ->  Bitmap Heap Scan on photos p  (cost=12.20..27.08 rows=48 width=220) (actual time=0.412..0.831 rows=48 loops=1)
        Recheck Cond: ((hashtags @> '{Damru26}'::text[]) AND (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid))
        Heap Blocks: exact=38
        ->  BitmapAnd  (cost=12.20..12.20 rows=48 width=0) (actual time=0.388..0.388 rows=0 loops=1)
              ->  Bitmap Index Scan on idx_photos_hashtags  (cost=0.00..6.11 rows=120 width=0) (actual time=0.201..0.201 rows=120 loops=1)
                    Index Cond: (hashtags @> '{Damru26}'::text[])
              ->  Bitmap Index Scan on idx_photos_college  (cost=0.00..5.84 rows=480 width=0) (actual time=0.148..0.148 rows=480 loops=1)
                    Index Cond: (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid)
Planning Time: 0.8 ms
Execution Time: 1.0 ms
```

### Interpretation

PostgreSQL's GIN index on `hashtags` supports the array containment operator `@>` natively. The planner generates a bitmap from both the GIN index and the college B-tree index, intersects them (BitmapAnd), and then fetches only the matching heap pages. Without the GIN index this query would require a sequential scan and an array element check on every row, which degrades linearly with table size.

---

## Q3 — Email Domain Lookup

**Purpose:** At onboarding, extract the domain from the user's Google email and find the matching college. This runs once per new user session.

**Tables involved:** `college_email_domains`, `colleges`

**Indexes used:**
- `idx_domains_domain` — B-tree on `college_email_domains(domain)` → equality lookup on a UNIQUE column

**Expected scan type:** Index Scan on `idx_domains_domain` (or Index Scan on the implicit unique index), then Nested Loop join to `colleges`

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT
    ced.college_id,
    c.name AS college_name
FROM   college_email_domains ced
JOIN   colleges c ON c.id = ced.college_id
WHERE  ced.domain = 'rishihood.edu.in';
```

### Expected Plan Output

```
Nested Loop  (cost=0.28..4.32 rows=1 width=48) (actual time=0.080..0.084 rows=1 loops=1)
  ->  Index Scan using idx_domains_domain on college_email_domains ced  (cost=0.14..2.16 rows=1 width=32) (actual time=0.062..0.064 rows=1 loops=1)
        Index Cond: (domain = 'rishihood.edu.in'::text)
  ->  Index Scan using colleges_pkey on colleges c  (cost=0.14..2.16 rows=1 width=36) (actual time=0.016..0.017 rows=1 loops=1)
        Index Cond: (id = ced.college_id)
Planning Time: 0.4 ms
Execution Time: 0.1 ms
```

### Interpretation

Because `domain` is UNIQUE, the index scan is guaranteed to return at most one row. The join to `colleges` on the PK is equally fast. The total execution time is sub-millisecond. This is essentially a point lookup — no seq scan risk regardless of table size.

---

## Q4 — Tag Lookup by Name and College

**Purpose:** Before saving a hashtag, the application checks whether a tag with the same `name` and `college_id` already exists. If it does, `usage_count` is incremented; if not, a new tag row is inserted.

**Tables involved:** `tags`

**Indexes used:**
- `idx_tags_name` — B-tree on `tags(name)` → filter on tag name
- `idx_tags_college` — B-tree on `tags(college_id)` → filter on college
- The composite `UNIQUE(college_id, name)` constraint also creates an implicit unique index which the planner may prefer for a combined equality lookup.

**Expected scan type:** Index Scan on the unique index for `(college_id, name)` — a single combined equality probe

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT id, usage_count
FROM   tags
WHERE  name       = 'Damru26'
  AND  college_id = 'a1b2c3d4-0000-0000-0000-rishihood001';
```

### Expected Plan Output

```
Index Scan using tags_college_id_name_key on tags  (cost=0.14..2.16 rows=1 width=24) (actual time=0.042..0.043 rows=1 loops=1)
  Index Cond: ((college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid) AND (name = 'Damru26'::text))
Planning Time: 0.3 ms
Execution Time: 0.05 ms
```

### Interpretation

The unique constraint on `(college_id, name)` means PostgreSQL can resolve this lookup with a single index probe, returning at most one row. The planner uses the implicit unique index rather than the separate single-column indexes (`idx_tags_name`, `idx_tags_college`) because the composite index is more selective. Execution time is negligible.

---

## Q5 — Popular Tags

**Purpose:** Retrieve the 20 most-used hashtags for a college to populate the "Popular Tags" panel in the gallery UI.

**Tables involved:** `tags`

**Indexes used:**
- `idx_tags_usage` — B-tree on `tags(usage_count DESC)` → satisfies ORDER BY without a sort step
- `idx_tags_college` — B-tree on `tags(college_id)` → narrows to one college

**Expected scan type:** Index Scan on `idx_tags_usage` with a filter on `college_id`, or a Bitmap Heap Scan combining both indexes for larger tag tables.

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT id, name, usage_count
FROM   tags
WHERE  college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'
ORDER BY usage_count DESC
LIMIT  20;
```

### Expected Plan Output

```
Limit  (cost=0.14..6.52 rows=20 width=52) (actual time=0.038..0.112 rows=20 loops=1)
  ->  Index Scan using idx_tags_usage on tags  (cost=0.14..48.90 rows=153 width=52) (actual time=0.036..0.108 rows=20 loops=1)
        Filter: (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid)
        Rows Removed by Filter: 12
Planning Time: 0.3 ms
Execution Time: 0.1 ms
```

### Interpretation

The `idx_tags_usage` index is defined as `(usage_count DESC)`, matching the query's `ORDER BY usage_count DESC` exactly. PostgreSQL can walk this index from the highest `usage_count` down, stopping as soon as 20 rows matching the `college_id` filter are found. No explicit sort step is needed. For a college with hundreds of tags, the LIMIT means only a small portion of the index is read.

---

## Q6 — Campus Engagement & Batch Year Analytics

**Purpose:** Aggregate student engagement and photo submission metrics grouped by academic batch year for institutional reporting.

**Tables involved:** `profiles`, `photos`

**Indexes used:**
- `idx_profiles_college` — B-tree on `profiles(college_id)`
- `idx_photos_uploader` — B-tree on `photos(uploader_id)`
- `idx_photos_college` — B-tree on `photos(college_id)`

**Expected scan type:** Hash Join or Merge Join with Hash Aggregate over batch years.

### EXPLAIN ANALYZE Command

```sql
EXPLAIN ANALYZE
SELECT
    pr.batch_year,
    COUNT(DISTINCT pr.id)          AS active_contributors,
    COUNT(p.id)                    AS total_photos_uploaded,
    ROUND(COUNT(p.id)::NUMERIC / NULLIF(COUNT(DISTINCT pr.id), 0), 2) AS avg_photos_per_contributor,
    MIN(p.uploaded_at)             AS earliest_upload,
    MAX(p.uploaded_at)             AS latest_upload
FROM   profiles pr
JOIN   photos p ON p.uploader_id = pr.id
WHERE  pr.college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'
  AND  p.is_approved = TRUE
GROUP BY pr.batch_year
ORDER BY pr.batch_year DESC;
```

### Expected Plan Output

```
Sort  (cost=124.50..124.62 rows=5 width=68) (actual time=2.150..2.155 rows=4 loops=1)
  Sort Key: pr.batch_year DESC
  Sort Method: quicksort  Memory: 25kB
  ->  HashAggregate  (cost=120.10..124.44 rows=5 width=68) (actual time=2.080..2.120 rows=4 loops=1)
        Group Key: pr.batch_year
        ->  Hash Join  (cost=15.20..112.50 rows=760 width=24) (actual time=0.450..1.720 rows=760 loops=1)
              Hash Cond: (p.uploader_id = pr.id)
              ->  Bitmap Heap Scan on photos p  (cost=8.10..98.40 rows=820 width=20) (actual time=0.210..0.980 rows=820 loops=1)
                    Recheck Cond: (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid)
                    Filter: is_approved
                    ->  Bitmap Index Scan on idx_photos_college  (cost=0.00..7.90 rows=850 width=0) (actual time=0.150..0.150 rows=850 loops=1)
              ->  Hash  (cost=5.80..5.80 rows=110 width=20) (actual time=0.210..0.210 rows=110 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 14kB
                    ->  Index Scan using idx_profiles_college on profiles pr  (cost=0.15..5.80 rows=110 width=20) (actual time=0.030..0.160 rows=110 loops=1)
                          Index Cond: (college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'::uuid)
Planning Time: 0.42 ms
Execution Time: 2.21 ms
```

### Interpretation

PostgreSQL efficiently filters active profiles using the `idx_profiles_college` index and builds an in-memory hash table. Simultaneously, approved photos are identified via the `idx_photos_college` bitmap index scan. The `HashAggregate` calculates distinct counts and timestamp minimums/maximums in a single pass before a lightweight sort step produces the final grouped output.

---

## Index Summary

| Query | Primary Index | Type | Scan Used |
|---|---|---|---|
| Q1 Gallery Load | `idx_photos_uploaded` | B-tree DESC | Index Scan (order elimination) |
| Q2 Hashtag Search | `idx_photos_hashtags` | GIN | Bitmap Index Scan |
| Q3 Domain Lookup | `idx_domains_domain` | B-tree UNIQUE | Index Scan |
| Q4 Tag Lookup | `tags_college_id_name_key` | B-tree UNIQUE | Index Scan |
| Q5 Popular Tags | `idx_tags_usage` | B-tree DESC | Index Scan (order elimination) |
| Q6 Batch Analytics | `idx_photos_college`, `idx_profiles_college` | B-tree | Bitmap Heap Scan + Hash Join |
