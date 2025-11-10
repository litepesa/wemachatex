# WemaChat Elixir Backend Architecture

**Version:** 1.0.0
**Date:** 2025-11-03
**Status:** Foundation Phase

---

## Vision: Super App for Kenya

WemaChat is a WeChat-inspired super app built specifically for the Kenyan market. This document outlines the technical architecture using Elixir/Phoenix with Umbrella project structure.

## Why Elixir + Umbrella?

### Technical Reasons:
1. **Real-Time Heavy**: Phoenix Channels natively handle millions of concurrent connections
2. **Fault Tolerance**: BEAM supervision trees - one feature crashes, others continue
3. **Concurrency**: Lightweight processes perfect for chat, live streaming, games
4. **Distribution**: Easy horizontal scaling when needed
5. **Maintainability**: Umbrella apps keep features isolated and organized

### Super App Features (Planned):
- ✅ **Launch Features** (6): Chats, Calls, Channels, Moments, Wallet, Gifts
- 🔄 **Phase 2**: Games, Live Streaming, Mini Programs
- 🔄 **Phase 3**: Payments (M-Pesa), E-commerce, Official Accounts
- 🔄 **Phase 4**: QR Codes, Red Packets, Location Services, News Feed

---

## Project Structure

```
wemachatex/                    # Umbrella root
├── apps/
│   ├── wemachat_core/         # Shared utilities, types, helpers
│   ├── wemachat_database/     # Ecto schemas, migrations, repos
│   ├── wemachat_api/          # Phoenix HTTP/WebSocket API layer
│   ├── wemachat_auth/         # Authentication & user management (future)
│   ├── wemachat_chat/         # Real-time messaging (future)
│   ├── wemachat_channels/     # Video content & feed (future)
│   ├── wemachat_moments/      # Stories/moments (future)
│   ├── wemachat_wallet/       # Virtual currency & payments (future)
│   ├── wemachat_games/        # Gaming center (future)
│   └── wemachat_live/         # Live streaming (future)
├── config/
│   ├── config.exs             # Shared configuration
│   ├── dev.exs                # Development environment
│   ├── test.exs               # Test environment
│   ├── prod.exs               # Production environment
│   └── runtime.exs            # Runtime configuration
└── mix.exs                    # Umbrella project definition
```

---

## Core Apps (Foundation)

### 1. wemachat_core
**Purpose:** Shared utilities, types, and helpers used across all apps

**Responsibilities:**
- Common types and structs
- Utility functions (date/time, string manipulation, validation)
- Shared constants and enums
- Error handling utilities
- Logging and telemetry helpers

**Dependencies:** None (pure Elixir)

**Example Modules:**
```elixir
WemachatCore.Types          # Common types
WemachatCore.Utils          # Utility functions
WemachatCore.Validation     # Input validation
WemachatCore.Constants      # App-wide constants
```

---

### 2. wemachat_database
**Purpose:** Database layer with Ecto schemas, repos, and migrations

**Responsibilities:**
- Ecto schemas for all domain models
- Database repository pattern
- Migrations management
- Query helpers and common queries
- Database connection pooling

**Dependencies:**
- `ecto` - Database wrapper
- `ecto_sql` - SQL adapter
- `postgrex` - PostgreSQL driver
- `jason` - JSON encoding/decoding
- `wemachat_core` - Shared types

**Key Modules:**
```elixir
WemachatDatabase.Repo           # Main Ecto repository
WemachatDatabase.Schemas.User   # User schema
WemachatDatabase.Schemas.Video  # Video schema
WemachatDatabase.Schemas.Chat   # Chat schema
# ... more schemas
```

**Database Design:**
- PostgreSQL 14+ (for JSONB, full-text search, trigrams)
- Connection pooling (100 connections max, 25 idle)
- Prepared statements for performance
- Indexes on all foreign keys and common queries
- Trigger functions for automatic count updates

---

### 3. wemachat_api
**Purpose:** Phoenix HTTP/WebSocket API layer - the public interface

**Responsibilities:**
- HTTP REST API endpoints
- WebSocket channels for real-time features
- Request/response serialization
- Authentication middleware
- CORS handling
- Rate limiting
- API versioning (v1, v2, etc.)

**Dependencies:**
- `phoenix` - Web framework
- `phoenix_ecto` - Ecto integration
- `plug_cowboy` - HTTP server
- `corsica` - CORS handling
- `wemachat_database` - Data access
- `wemachat_core` - Shared utilities

**Key Endpoints:**
```
POST   /api/v1/auth/sync              # Sync Firebase user
GET    /api/v1/users/:id              # Get user profile
POST   /api/v1/users/:id/follow       # Follow user
GET    /api/v1/videos                 # List videos (feed)
POST   /api/v1/videos                 # Upload video
POST   /api/v1/videos/:id/like        # Like video
WS     /socket                        # WebSocket connection
```

**Channels:**
```elixir
WemachatApiWeb.UserSocket          # Socket authentication
WemachatApiWeb.ChatChannel         # Real-time chat
WemachatApiWeb.PresenceChannel     # Online presence
WemachatApiWeb.CallChannel         # Voice/video calls
```

---

## Future Apps (Feature Modules)

### wemachat_auth
- Firebase Admin SDK integration
- User registration and profile management
- Phone OTP verification
- Session management
- Role-based access control (admin, host, guest)

### wemachat_chat
- 1-on-1 messaging
- Group chats
- Message delivery and read receipts
- Typing indicators
- Message history and search
- Media attachments

### wemachat_videos (formerly wemachat_channels)
- **Status:** Videos are now user-based (not channel-based)
- Video feed management
- Video upload and processing
- Content moderation
- Trending algorithms
- Search and discovery

**Note:** As of 2025-11-06:
- Old channel system completely removed
- Videos belong directly to users (via `user_id`)
- New WhatsApp/Telegram-style channels feature coming soon
- See `VIDEO_MIGRATION_NOTES.md` for details

### wemachat_moments
- Stories/moments feed
- Image/video posts with 24h expiry
- Likes and comments
- Privacy controls (public/friends only)

### wemachat_wallet
- Virtual coin wallet
- Coin purchase (M-Pesa integration)
- Transactions and history
- Virtual gifts
- Premium content purchases

### wemachat_games
- Mini games catalog
- Multiplayer game rooms
- Leaderboards
- Game state management
- Turn-based and real-time games

### wemachat_live
- Live streaming (Agora SDK)
- Stream management
- Viewer presence
- Live comments
- Virtual gifts during streams

---

## Inter-App Communication

### Pattern 1: Direct Function Calls
For synchronous operations within the same BEAM instance:
```elixir
# In wemachat_api controller
user = WemachatDatabase.Repo.get(User, user_id)
WemachatAuth.verify_permissions(user, :create_video)
```

### Pattern 2: PubSub for Events
For async event broadcasting across apps:
```elixir
# In wemachat_chat when message sent
Phoenix.PubSub.broadcast(
  Wemachat.PubSub,
  "user:#{recipient_id}",
  {:new_message, message}
)

# In wemachat_api WebSocket
def handle_info({:new_message, message}, socket) do
  push(socket, "new_message", message)
  {:noreply, socket}
end
```

### Pattern 3: GenServer for State
For stateful services (online users, game rooms, etc.):
```elixir
# In wemachat_chat
WemachatChat.PresenceServer.mark_online(user_id)
WemachatChat.PresenceServer.get_online_friends(user_id)
```

---

## Database Layer Design

### Ecto Repository Pattern
Single shared repository accessed by all apps:
```elixir
# All apps use same repo
alias WemachatDatabase.Repo
alias WemachatDatabase.Schemas.{User, Video, Chat}

# Standard queries
Repo.get(User, id)
Repo.insert(changeset)
Repo.update(changeset)
Repo.delete(user)

# Custom queries in schemas
User.by_phone(phone_number)
Video.trending(limit: 50)
Chat.unread_count(user_id)
```

### Migration Strategy
Migrations live in `wemachat_database/priv/repo/migrations/`:
```bash
# Create migration
cd apps/wemachat_database
mix ecto.gen.migration create_users_table

# Run migrations (from umbrella root)
mix ecto.migrate

# Rollback
mix ecto.rollback
```

### Schema Organization
```
apps/wemachat_database/lib/wemachat_database/schemas/
├── user.ex
├── video.ex
├── chat.ex
├── message.ex
├── comment.ex
├── wallet.ex
└── transaction.ex
```

---

## Configuration Strategy

### Environment-Based Config
```elixir
# config/dev.exs
config :wemachat_database, WemachatDatabase.Repo,
  username: "postgres",
  password: "postgres",
  database: "wemachat_dev",
  hostname: "localhost",
  pool_size: 10

# config/prod.exs
config :wemachat_database, WemachatDatabase.Repo,
  pool_size: 100,
  queue_target: 5000

# config/runtime.exs (for secrets)
config :wemachat_database, WemachatDatabase.Repo,
  url: System.get_env("DATABASE_URL")
```

### Shared Configuration
All apps inherit umbrella config but can override:
```elixir
# apps/wemachat_api/config/config.exs
use Mix.Config

# Import umbrella config
import_config "../../config/config.exs"

# API-specific config
config :wemachat_api, WemachatApiWeb.Endpoint,
  url: [host: "localhost"],
  http: [port: 4000]
```

---

## Development Workflow

### Starting the App
```bash
# From umbrella root
cd wemachatex

# Install dependencies
mix deps.get

# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Start Phoenix server (all apps)
mix phx.server

# Or in IEx
iex -S mix phx.server
```

### Running Tests
```bash
# All apps
mix test

# Specific app
cd apps/wemachat_database
mix test

# With coverage
mix test --cover
```

### Adding a New Feature App
```bash
cd apps
mix new wemachat_games --sup

# Or Phoenix context
cd apps/wemachat_api
mix phx.gen.context Games Game games name:string players:integer
```

---

## Deployment Strategy

### Release with Mix Release
```bash
# Build production release
MIX_ENV=prod mix release

# Release includes all umbrella apps
_build/prod/rel/wemachatex/bin/wemachatex start
```

### Docker Deployment
```dockerfile
FROM elixir:1.16-alpine

# Install dependencies
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy umbrella project
COPY . /app
WORKDIR /app

# Install dependencies and compile
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix compile

# Build release
RUN MIX_ENV=prod mix release

# Run
CMD ["_build/prod/rel/wemachatex/bin/wemachatex", "start"]
```

### Kubernetes Deployment
Each umbrella app can scale independently:
```yaml
# Database app - stateful
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: wemachat-database

# API app - stateless, scale horizontally
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wemachat-api
spec:
  replicas: 5
```

---

## Performance Considerations

### Connection Pooling
- Database: 100 max connections, 25 idle
- Redis: 50 connections per node
- Agora SDK: Pooled HTTP client

### Caching Strategy
1. **ETS tables**: In-memory cache for hot data (users online, trending videos)
2. **Redis**: Distributed cache for session data, rate limiting
3. **Database**: PostgreSQL query cache + prepared statements

### WebSocket Scaling
- Phoenix Channels use PubSub (pg2 for single node, Redis for multi-node)
- Each node can handle 100k+ concurrent connections
- Horizontal scaling: Add more nodes, PubSub syncs state

---

## Monitoring & Observability

### Telemetry
```elixir
# All apps emit telemetry events
:telemetry.execute(
  [:wemachat_chat, :message, :sent],
  %{count: 1},
  %{user_id: user_id}
)

# Attach handlers in wemachat_api
:telemetry.attach_many(
  "wemachat-telemetry",
  [
    [:phoenix, :endpoint, :start],
    [:phoenix, :endpoint, :stop],
    [:wemachat_database, :repo, :query]
  ],
  &WemachatApiWeb.Telemetry.handle_event/4,
  nil
)
```

### Logging
- Structured logging with `Logger`
- Request ID tracking across apps
- Error tracking with Sentry (future)
- APM with New Relic or AppSignal (future)

---

## Security

### Authentication
- Firebase JWT verification in `wemachat_auth`
- Plugs in `wemachat_api` for route protection
- Role-based access control (RBAC)

### Rate Limiting
- Hammer library for distributed rate limiting
- Per-IP and per-user limits
- Different limits for different endpoints

### Input Validation
- Ecto changesets for all data mutations
- Custom validators in `wemachat_core`
- SQL injection protection via parameterized queries
- XSS protection in JSON responses

---

## Migration from Go Backend

### Data Migration
1. Export data from Go backend PostgreSQL
2. Transform to Elixir schema format
3. Import using Ecto.Multi for transactions
4. Verify data integrity

### API Compatibility
- Keep same REST endpoints and JSON format
- Flutter app should work without changes
- Update base URL in Flutter config

### Feature Parity Checklist
- [ ] User authentication (Firebase)
- [ ] User profiles and demographics
- [ ] Video upload and streaming
- [ ] Comments with media
- [ ] Likes, follows, shares
- [ ] Video reactions chat (WebSocket)
- [ ] Wallet and transactions
- [ ] Virtual gifts
- [ ] Search (fuzzy + full-text)
- [ ] Premium videos

---

## Next Steps

### Phase 1: Foundation (Current)
- [x] Create umbrella project
- [x] Set up core apps (core, database, API)
- [ ] Configure Ecto and PostgreSQL
- [ ] Set up Phoenix API with basic routes
- [ ] Configure CORS and middleware
- [ ] Add telemetry and logging

### Phase 2: User Management
- [ ] Create user schemas and migrations
- [ ] Implement Firebase authentication
- [ ] User profile CRUD operations
- [ ] Follow/unfollow functionality
- [ ] User search

### Phase 3: Content (Channels)
- [ ] Video schemas and migrations
- [ ] Video upload with Cloudflare R2
- [ ] Video feed with pagination
- [ ] Like, comment, share
- [ ] Trending algorithm

### Phase 4: Real-Time (Chat)
- [ ] WebSocket setup with Phoenix Channels
- [ ] 1-on-1 chat
- [ ] Message delivery and read receipts
- [ ] Typing indicators
- [ ] Online presence

### Phase 5: Wallet & Payments
- [ ] Wallet schemas
- [ ] Virtual coins and transactions
- [ ] M-Pesa integration (future)
- [ ] Virtual gifts
- [ ] Premium content purchases

---

## Technical Decisions Log

### 2025-11-03: Switch from Go to Elixir
**Reason:** Super app vision requires real-time heavy features (chat, live, games) where Elixir/Phoenix excels. Umbrella architecture perfectly matches modular super app needs. Early enough to switch before adding 6+ more features.

**Trade-offs:** Need to rewrite existing Go backend (15 migrations, 8 features), but cost is lowest now vs. later.

**Decision:** Proceed with Elixir + Umbrella

---

## Resources

- [Elixir Official Guide](https://elixir-lang.org/getting-started/introduction.html)
- [Phoenix Framework](https://hexdocs.pm/phoenix)
- [Ecto Documentation](https://hexdocs.pm/ecto)
- [Umbrella Projects](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html)
- [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html)
- [Production Deployment](https://hexdocs.pm/phoenix/deployment.html)
