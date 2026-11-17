# CampusLens — Academic DBMS Project (AP 2026)

> **CampusLens** is a campus-exclusive photo-sharing and archival platform designed for college communities to capture, preserve, and search memories across campus events, fests, and clubs.

- **Main Application Repository:** [https://github.com/Garvit-png/CampLens.git](https://github.com/Garvit-png/CampLens.git)
- **Course / Track:** Database Management Systems (DBMS) Academic Coursework 2026
- **Database Engine:** PostgreSQL (Supabase)

---

## 👥 Project Team

- **Garvit Gandhi** — Architecture, Supabase Configuration & Core Engineering
- **Japinder Kaur** — Database Design, Normalization, Query Optimization & Analysis
- **Keshav Birla** — Backend Integration, APIs & Data Modeling
- **Vansh** — Frontend Interfaces, Component Structure & UI/UX

---

## 📂 DBMS Deliverables & Artifacts (`dbms/`)

This repository contains the end-to-end relational database design, formal normalization proofs, entity-relationship diagrams, schema definitions, production queries, and query execution plans for CampusLens:

| Deliverable | File | Description |
|---|---|---|
| **CP1** | [`dbms/01_normalization.md`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/01_normalization.md) | Formal functional dependency and Normal Form analysis (1NF, 2NF, 3NF, BCNF) with explicit denormalization trade-offs. |
| **CP2** | [`dbms/02_er_diagram.md`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/02_er_diagram.md) | Conceptual and logical Entity-Relationship (ER) model with cardinality constraints and relational mapping. |
| **CP3** | [`dbms/03_schema.sql`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/03_schema.sql) | Complete DDL script for PostgreSQL/Supabase including tables, indexes, triggers, and Row Level Security (RLS) policies. |
| **CP4** | [`dbms/04_queries.sql`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/04_queries.sql) | Parametrized production SQL queries covering gallery loading, tag searching, domain lookups, and analytics. |
| **CP5** | [`dbms/05_query_timings.md`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/05_query_timings.md) | `EXPLAIN ANALYZE` execution plans, index scans, cost estimations, and join optimization benchmarks. |
| **Execution Plans** | [`dbms/plans/`](file:///Users/japinderkaur/Downloads/Japinder's%20Space/DE%20Repo/CampusLens_AP_2026/dbms/plans) | Raw query execution plans for individual core queries. |

---

## 🛠️ Schema Architecture Overview

The database schema models campus multi-tenancy and media association:

1. **`colleges`**: Multi-tenant institutions registered on the platform.
2. **`college_email_domains`**: Whitelisted domains ensuring email verification and automatic institutional affiliation.
3. **`profiles`**: User profiles mapped 1:1 with authenticated users (`auth.users`), linked to their respective college.
4. **`events`**: Campus events and fests categorizing photo submissions.
5. **`photos`**: Uploaded media records with Cloudinary public IDs, hashtags, moderation flags, and timestamps.
6. **`tags`**: Reusable tags scoped per college with usage frequency tracking.
7. **`photo_tags`**: Many-to-many junction bridge associating photos with tags.

---

## 🚀 Running the Schema

1. Open the [Supabase SQL Editor](https://app.supabase.com) or connect to your local PostgreSQL instance:
   ```bash
   psql -h <host> -U <user> -d <database> -f dbms/03_schema.sql
   ```
2. The schema creates tables in topological dependency order, establishes foreign keys with cascading rules, configures RLS policies, and inserts seed data for testing.
