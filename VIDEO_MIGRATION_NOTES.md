# Video System Migration: Channel-Based → User-Based

**Date:** November 6, 2025
**Status:** ✅ Completed
**Migration Version:** 20251106000001

---

## Overview

The Elixir backend has been updated to change videos from **channel-based** to **user-based**, matching the Flutter app's implementation.

### What Changed

Previously, videos belonged to channels (one channel per user):
```
User → Channel → Videos
```

Now, videos belong directly to users:
```
User → Videos
```

---

## Changes Made

### 1. Database Schema (`apps/wemachat_database/lib/wemachat_database/schemas/video.ex`)

**Before:**
```elixir
field :channel_id, :binary_id
belongs_to :channel, WemachatDatabase.Schemas.Channel
```

**After:**
```elixir
field :user_id, :string
belongs_to :user, WemachatDatabase.Schemas.User, type: :string
```

### 2. Database Migration (`20251106000001_convert_videos_to_user_based.exs`)

Created a migration that:
- ✅ Adds `user_id` column to `videos` table
- ✅ Migrates data from `channel_id` to `user_id` (using channels table as intermediary)
- ✅ Removes `channel_id` foreign key constraint
- ✅ Drops `channel_id` column
- ✅ Adds `user_id` foreign key to users table
- ✅ Creates index on `user_id`

**Rollback Support:**
The migration includes a `down` function to rollback changes if needed (assumes channels still exist).

### 3. Videos Context (`apps/wemachat_core/lib/wemachat_core/contexts/videos.ex`)

**Function Changes:**

| Old Function | New Function | Description |
|--------------|--------------|-------------|
| `list_channel_videos(channel_id, opts)` | `list_user_videos(user_id, opts)` | Get videos by user |
| Uses `Channels.get_channel()` | Uses `Users.get_user()` | Get user/channel |
| Uses `Channels.increment_videos()` | Uses `Users.increment_videos()` | Increment video count |
| Uses `Channels.decrement_videos()` | Uses `Users.decrement_videos()` | Decrement video count |

**Context Updates:**
- ✅ Changed `alias WemachatCore.Contexts.Channels` to `alias WemachatCore.Contexts.Users`
- ✅ Updated all channel references to user references
- ✅ Updated error messages (`:channel_not_found` → `:user_not_found`)

### 4. Video Controller (`apps/wemachat_api/lib/wemachat_api_web/controllers/video_controller.ex`)

**Route Changes:**

| Old Route | New Route |
|-----------|-----------|
| `GET /api/v1/channels/:channel_id/videos` | `GET /api/v1/users/:user_id/videos` |

**Function Changes:**

| Old Function | New Function |
|--------------|--------------|
| `channel_videos/2` | `user_videos/2` |

**Response Format Changes:**

The `format_video/1` helper now returns:
```elixir
%{
  userId: video.user_id,      # ✅ NEW (instead of channelId)
  user_id: video.user_id,     # ✅ NEW (instead of channel_id)
  # ... rest of fields remain the same
}
```

**Auth Updates:**
```elixir
# Before
plug FirebaseAuth when action not in [..., :channel_videos, ...]

# After
plug FirebaseAuth when action not in [..., :user_videos, ...]
```

### 5. Router (`apps/wemachat_api/lib/wemachat_api_web/router.ex`)

**Route Changes:**
```elixir
# Before
get "/channels/:channel_id/videos", VideoController, :channel_videos

# After
get "/users/:user_id/videos", VideoController, :user_videos
```

---

## What Was Removed

### ❌ Old Channels System (Completely Removed)

The old channel system has been completely removed to make way for a new WhatsApp/Telegram-style channels feature:
- ❌ `channels` table dropped
- ❌ `channel_follows` table dropped
- ❌ `ChannelController` deleted
- ❌ All channel routes removed
- ❌ Channel contexts and schemas deleted

**Rationale:** The old channel system (one channel per user for video posting) has been replaced with user-based videos. A new channels feature (similar to WhatsApp/Telegram broadcast channels) will be implemented separately in the future.

---

## Flutter App Compatibility

The Flutter app (`textgb/`) expects user-based videos:

**VideoModel (`textgb/lib/features/videos/models/video_model.dart`):**
```dart
class VideoModel {
  final String userId;      // ✅ Matches new backend
  final String userName;
  // ...
}
```

**Backend Response:**
```json
{
  "id": "uuid",
  "userId": "firebase_uid",     // ✅ Now provided
  "user_id": "firebase_uid",    // ✅ Now provided (snake_case)
  "videoUrl": "https://...",
  "caption": "My video",
  // ... rest of fields
}
```

---

## API Endpoint Changes

### Old Endpoint (Deprecated)
```
GET /api/v1/channels/:channel_id/videos?page=1&per_page=20
```

### New Endpoint (Current)
```
GET /api/v1/users/:user_id/videos?page=1&per_page=20
```

### All Other Endpoints (Unchanged)
```
GET  /api/v1/videos/feed
GET  /api/v1/videos/discover
GET  /api/v1/videos/search?q=query
GET  /api/v1/videos/:id
POST /api/v1/videos
PUT  /api/v1/videos/:id
DELETE /api/v1/videos/:id
POST /api/v1/videos/:id/like
DELETE /api/v1/videos/:id/like
POST /api/v1/videos/:id/share
POST /api/v1/videos/:id/comments
GET  /api/v1/videos/:id/comments
```

---

## Migration Instructions

### For Development

1. **Run the migration:**
   ```bash
   cd wemachatex
   mix ecto.migrate
   ```

2. **Verify migration:**
   ```bash
   mix ecto.migrations
   ```
   Should show: `up    20251106000001  convert_videos_to_user_based`

3. **Check database:**
   ```sql
   -- Check videos table has user_id
   \d videos

   -- Verify data migration
   SELECT id, user_id, caption FROM videos LIMIT 5;
   ```

### For Production

1. **Backup database before migration:**
   ```bash
   pg_dump -h localhost -U postgres wemachat_prod > backup_pre_video_migration.sql
   ```

2. **Run migration in production:**
   ```bash
   MIX_ENV=prod mix ecto.migrate
   ```

3. **Verify data integrity:**
   ```sql
   -- Count videos before (should match after)
   SELECT COUNT(*) FROM videos;

   -- Check user_id is populated
   SELECT COUNT(*) FROM videos WHERE user_id IS NOT NULL;

   -- Verify user_id references valid users
   SELECT v.id, v.user_id, u.name
   FROM videos v
   LEFT JOIN users u ON v.user_id = u.id
   WHERE u.id IS NULL;  -- Should return 0 rows
   ```

### Rollback (If Needed)

**⚠️ Warning:** Rollback is NOT supported for this migration!

The old channel system has been completely removed. If you need to revert, you must:
1. Restore from a database backup taken before this migration
2. Or manually recreate the old channel tables from the previous migration file

---

## Breaking Changes

### ❌ Removed - Videos
- `GET /api/v1/channels/:channel_id/videos` endpoint
- `channel_videos/2` controller action
- `list_channel_videos/2` context function
- `channelId` / `channel_id` fields in video JSON responses

### ❌ Removed - Channels (Entire System)
- `GET /api/v1/channels` - List channels
- `GET /api/v1/channels/verified` - Verified channels
- `GET /api/v1/channels/featured` - Featured channels
- `GET /api/v1/channels/search` - Search channels
- `GET /api/v1/channels/user/:user_id` - User's channel
- `GET /api/v1/channels/:id` - Channel details
- `POST /api/v1/channels` - Create channel
- `PUT /api/v1/channels/:id` - Update channel
- `POST /api/v1/channels/:id/follow` - Follow channel
- `DELETE /api/v1/channels/:id/follow` - Unfollow channel
- All channel-related models, contexts, and controllers

### ✅ Added
- `GET /api/v1/users/:user_id/videos` endpoint
- `user_videos/2` controller action
- `list_user_videos/2` context function
- `userId` / `user_id` fields in video JSON responses

### ⚠️ Client Impact
**Flutter app:** Already expects `userId` field - **no changes needed** ✅

**Other clients:** If you have other clients (web, mobile, etc.) that use the old channel-based endpoints, they will need to be updated.

---

## Database Schema Comparison

### Before
```sql
CREATE TABLE videos (
  id UUID PRIMARY KEY,
  channel_id UUID NOT NULL REFERENCES channels(id),
  video_url TEXT NOT NULL,
  -- ...
);

CREATE INDEX videos_channel_id_idx ON videos(channel_id);
```

### After
```sql
CREATE TABLE videos (
  id UUID PRIMARY KEY,
  user_id VARCHAR NOT NULL REFERENCES users(id),
  video_url TEXT NOT NULL,
  -- ...
);

CREATE INDEX videos_user_id_idx ON videos(user_id);
```

---

## Testing Checklist

- [ ] Migration runs successfully without errors
- [ ] All videos have non-null `user_id` after migration
- [ ] All `user_id` values reference valid users
- [ ] Video count matches before and after migration
- [ ] `GET /api/v1/users/:user_id/videos` returns videos
- [ ] Video creation works with `user_id`
- [ ] Video deletion decrements user's `videos_count`
- [ ] Feed endpoints still work
- [ ] Search endpoint still works
- [ ] Like/unlike functionality unchanged
- [ ] Comment functionality unchanged
- [ ] Flutter app can fetch and display videos

---

## Notes

1. **72-Hour Expiry:** Videos still expire after 72 hours as before
2. **User Metrics:** User's `videos_count` is automatically updated when videos are created/deleted
3. **Channel System:** Remains available for future features (business accounts, creator profiles, etc.)
4. **Backward Compatibility:** Old channel routes removed - clients must update to new user-based routes

---

## Support

For questions or issues with this migration, refer to:
- Migration file: `apps/wemachat_database/priv/repo/migrations/20251106000001_convert_videos_to_user_based.exs`
- Video schema: `apps/wemachat_database/lib/wemachat_database/schemas/video.ex`
- Videos context: `apps/wemachat_core/lib/wemachat_core/contexts/videos.ex`
- Video controller: `apps/wemachat_api/lib/wemachat_api_web/controllers/video_controller.ex`
