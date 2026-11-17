-- ============================================================
-- CP3 — CampusLens Application Queries
-- ============================================================
-- All queries are valid PostgreSQL / Supabase SQL.
-- Placeholder values used:
--   college_id  : 'a1b2c3d4-0000-0000-0000-rishihood001'  (sample UUID)
--   uploader_id : 'a1b2c3d4-0000-0000-0000-profile00001'  (sample profile UUID)
--   event_id    : 'a1b2c3d4-0000-0000-0000-event000001'   (sample event UUID)
--   user_id     : 'a1b2c3d4-0000-0000-0000-authuser0001'  (sample auth.users UUID)
--   photo_id    : 'a1b2c3d4-0000-0000-0000-photo000001'   (sample photo UUID)
--   tag_id      : 'a1b2c3d4-0000-0000-0000-tagid000001'   (sample tag UUID)
--   domain      : 'rishihood.edu.in'
--   tag name    : 'Damru26'
-- ============================================================


-- ============================================================
-- Q1: Gallery Load
-- ============================================================
-- Purpose  : Load the main gallery for a college.
-- App file : lib/session.tsx → loadPhotos(collegeId)
-- Returns  : Up to 200 approved photos with uploader name and
--            event name, newest first.
-- ============================================================
SELECT
    p.id,
    p.image_url,
    p.thumbnail_url,
    p.caption,
    p.hashtags,
    p.year,
    p.uploaded_at,
    p.event_id,
    p.college_id,
    p.uploader_id,
    pr.full_name        AS uploader_full_name,
    e.name              AS event_name
FROM   photos p
JOIN   profiles pr ON pr.id = p.uploader_id
LEFT JOIN events e  ON e.id  = p.event_id
WHERE  p.college_id  = 'a1b2c3d4-0000-0000-0000-rishihood001'
  AND  p.is_approved = TRUE
ORDER BY p.uploaded_at DESC
LIMIT  200;


-- ============================================================
-- Q2: College Lookup by Email Domain
-- ============================================================
-- Purpose  : Given a user's email domain, find the matching college.
-- App file : app/onboarding/page.tsx
-- Returns  : college_id and college name, or NULL if unregistered.
-- ============================================================
SELECT
    ced.college_id,
    c.name AS college_name
FROM   college_email_domains ced
JOIN   colleges c ON c.id = ced.college_id
WHERE  ced.domain = 'rishihood.edu.in';


-- ============================================================
-- Q3: Profile Upsert
-- ============================================================
-- Purpose  : Create a new profile or update an existing one after
--            the student completes onboarding.
-- App file : app/onboarding/page.tsx
-- Note     : ON CONFLICT targets the UNIQUE constraint on user_id.
-- ============================================================
INSERT INTO profiles (
    user_id,
    college_id,
    full_name,
    batch_year,
    is_onboarding_complete
)
VALUES (
    'a1b2c3d4-0000-0000-0000-authuser0001',
    'a1b2c3d4-0000-0000-0000-rishihood001',
    'Garvit Sharma',
    2027,
    TRUE
)
ON CONFLICT (user_id) DO UPDATE
    SET college_id              = EXCLUDED.college_id,
        full_name               = EXCLUDED.full_name,
        batch_year              = EXCLUDED.batch_year,
        is_onboarding_complete  = EXCLUDED.is_onboarding_complete,
        updated_at              = NOW();


-- ============================================================
-- Q4: Photo INSERT
-- ============================================================
-- Purpose  : Save uploaded photo metadata after Cloudinary upload.
-- App file : app/api/photos/route.ts (POST handler)
-- Note     : Cloudinary stores the actual image; only URLs go here.
-- ============================================================
INSERT INTO photos (
    college_id,
    uploader_id,
    event_id,
    caption,
    hashtags,
    cloudinary_public_id,
    image_url,
    thumbnail_url,
    year,
    is_approved
)
VALUES (
    'a1b2c3d4-0000-0000-0000-rishihood001',
    'a1b2c3d4-0000-0000-0000-profile00001',
    'a1b2c3d4-0000-0000-0000-event000001',
    'Damru 2026 opening night',
    ARRAY['Damru26', 'Night', 'Music'],
    'campuslens/ru/photos/abc123xyz',
    'https://res.cloudinary.com/campuslens/image/upload/v1/campuslens/ru/photos/abc123xyz',
    'https://res.cloudinary.com/campuslens/image/upload/w_400/campuslens/ru/photos/abc123xyz',
    2026,
    TRUE
)
RETURNING id;


-- ============================================================
-- Q5: Event INSERT
-- ============================================================
-- Purpose  : Create a new event when the user clicks "+ New event"
--            on the upload form.
-- App file : app/(main)/upload/page.tsx
-- ============================================================
INSERT INTO events (
    college_id,
    name,
    year
)
VALUES (
    'a1b2c3d4-0000-0000-0000-rishihood001',
    'Damru 2026',
    2026
)
RETURNING id, name, year;


-- ============================================================
-- Q6: Tag Check + Upsert
-- ============================================================
-- Purpose  : Before linking a tag to a photo, check whether the tag
--            already exists for this college. The app performs these
--            as two sequential queries: first SELECT, then INSERT if
--            the SELECT returns no row. This avoids incrementing
--            usage_count on a duplicate insert.
-- App file : lib/hashtags.ts → saveHashtagsToDatabase()
-- ============================================================

-- Step 6a: Check if the tag already exists
SELECT id, usage_count
FROM   tags
WHERE  name       = 'Damru26'
  AND  college_id = 'a1b2c3d4-0000-0000-0000-rishihood001';

-- Step 6b: If the above returns no row, insert the new tag
--          (usage_count starts at 1 for a brand-new tag)
INSERT INTO tags (name, college_id, usage_count)
VALUES ('Damru26', 'a1b2c3d4-0000-0000-0000-rishihood001', 1)
RETURNING id;


-- ============================================================
-- Q7: Tag usage_count Increment
-- ============================================================
-- Purpose  : Increment the counter when an existing tag is reused.
-- App file : lib/hashtags.ts → saveHashtagsToDatabase()
-- ============================================================
UPDATE tags
SET    usage_count = usage_count + 1
WHERE  id = 'a1b2c3d4-0000-0000-0000-tagid000001';


-- ============================================================
-- Q8: Photo-Tag Link
-- ============================================================
-- Purpose  : Create the many-to-many link between a photo and a tag.
--            ON CONFLICT DO NOTHING silently skips duplicate links.
-- App file : lib/hashtags.ts → saveHashtagsToDatabase()
-- ============================================================
INSERT INTO photo_tags (photo_id, tag_id)
VALUES (
    'a1b2c3d4-0000-0000-0000-photo000001',
    'a1b2c3d4-0000-0000-0000-tagid000001'
)
ON CONFLICT (photo_id, tag_id) DO NOTHING;


-- ============================================================
-- Q9: Hashtag Search
-- ============================================================
-- Purpose  : Find all approved photos in a college that contain a
--            specific hashtag. Uses the GIN index on hashtags.
-- App file : app/api/search/route.ts (intended — currently returns
--            mock data; real query shown here for reference)
-- Index    : idx_photos_hashtags (GIN on hashtags TEXT[])
-- ============================================================
SELECT
    p.id,
    p.image_url,
    p.thumbnail_url,
    p.caption,
    p.hashtags,
    p.uploaded_at
FROM   photos p
WHERE  p.hashtags  @> ARRAY['Damru26']
  AND  p.college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'
ORDER BY p.uploaded_at DESC;


-- ============================================================
-- Q10: Gallery Filter — by Year and Event
-- ============================================================
-- Purpose  : Filter gallery photos by academic year and event.
--            In the app this filter is applied client-side;
--            this is the equivalent server-side query.
-- App file : components/GalleryView.tsx (client-side equivalent)
-- ============================================================
SELECT
    p.id,
    p.image_url,
    p.thumbnail_url,
    p.caption,
    p.hashtags,
    p.year,
    p.uploaded_at
FROM   photos p
WHERE  p.college_id  = 'a1b2c3d4-0000-0000-0000-rishihood001'
  AND  p.is_approved = TRUE
  AND  p.year        = 2026
  AND  p.event_id    = 'a1b2c3d4-0000-0000-0000-event000001'
ORDER BY p.uploaded_at DESC;


-- ============================================================
-- Q11: Popular Tags
-- ============================================================
-- Purpose  : Retrieve the 20 most-used hashtags for a college,
--            for the "Popular Tags" panel in the gallery UI.
-- App file : components/GalleryView.tsx (client-side currently;
--            this is the equivalent DB query)
-- Index    : idx_tags_usage (usage_count DESC)
-- ============================================================
SELECT
    id,
    name,
    usage_count
FROM   tags
WHERE  college_id = 'a1b2c3d4-0000-0000-0000-rishihood001'
ORDER BY usage_count DESC
LIMIT  20;


-- ============================================================
-- Q12: Photos by Uploader (Profile Page)
-- ============================================================
-- Purpose  : List all photos uploaded by a specific student.
--            Used on the profile page to show "my uploads".
-- App file : app/(main)/profile/page.tsx
-- ============================================================
SELECT
    p.id,
    p.image_url,
    p.thumbnail_url,
    p.caption,
    p.hashtags,
    p.uploaded_at,
    p.year
FROM   photos p
WHERE  p.uploader_id = 'a1b2c3d4-0000-0000-0000-profile00001'
ORDER BY p.uploaded_at DESC;


-- ============================================================
-- Q13: Photo DELETE (Owner Check Inline)
-- ============================================================
-- Purpose  : Delete a photo, enforcing that only the uploader can
--            remove it. The WHERE clause on uploader_id acts as an
--            inline ownership check — if the IDs do not match,
--            zero rows are affected and no error is raised.
-- App file : RLS policy "photos_delete" enforces the same rule
--            at the database level as a belt-and-suspenders guard.
-- ============================================================
DELETE FROM photos
WHERE  id          = 'a1b2c3d4-0000-0000-0000-photo000001'
  AND  uploader_id = 'a1b2c3d4-0000-0000-0000-profile00001';


-- ============================================================
-- Q14: Report Photo (Moderation — Set is_approved = FALSE)
-- ============================================================
-- Purpose  : Flag a photo for moderation by setting is_approved
--            to FALSE. The photo immediately disappears from gallery
--            queries (which filter WHERE is_approved = TRUE).
-- App file : components/ReportButton.tsx
-- ============================================================
UPDATE photos
SET    is_approved = FALSE
WHERE  id = 'a1b2c3d4-0000-0000-0000-photo000001';
