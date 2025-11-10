# WemaChat API - Development Setup Guide

This guide will help you set up your local development environment for the WemaChat API.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Elixir** 1.14 or higher
- **Erlang/OTP** 25 or higher
- **PostgreSQL** 14 or higher (or access to a hosted PostgreSQL instance)
- **Git**

Check your versions:
```bash
elixir --version
psql --version
git --version
```

## Step 1: Clone the Repository

```bash
git clone <your-repository-url>
cd wemachatex
```

## Step 2: Install Dependencies

Install all Elixir dependencies:

```bash
mix deps.get
```

## Step 3: Environment Configuration

### 3.1 Create Environment File

Copy the example environment file and configure your credentials:

```bash
cp .env.example .env
```

### 3.2 Configure Environment Variables

Open `.env` in your text editor and configure the following sections:

#### Server Configuration

```env
PHX_SERVER=true
PORT=4000
SECRET_KEY_BASE=<generate-with-mix-phx-gen-secret>
```

Generate a secure secret key base:
```bash
mix phx.gen.secret
```

Copy the output and paste it as the `SECRET_KEY_BASE` value.

#### Database Configuration

**Option A: Local PostgreSQL**
```env
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=wemachat_dev
DB_SSL=false
DB_POOL_SIZE=3
```

**Option B: Hosted PostgreSQL (DigitalOcean, AWS RDS, etc.)**
```env
DB_HOST=your-database-host.com
DB_PORT=25060
DB_USER=your-username
DB_PASSWORD=your-password
DB_NAME=your-database-name
DB_SSL=true
DB_POOL_SIZE=10
```

#### Firebase Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create a new one)
3. Navigate to **Project Settings** > **General**
4. Copy the **Project ID** and **Web API Key**

```env
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_WEB_API_KEY=your-web-api-key
```

5. Navigate to **Project Settings** > **Service Accounts**
6. Click **Generate New Private Key**
7. Save the JSON file to `apps/wemachat_api/priv/` directory
8. Update the path in `.env`:

```env
FIREBASE_CREDENTIALS_PATH=apps/wemachat_api/priv/your-firebase-adminsdk.json
```

#### Cloudflare R2 Storage Configuration

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Go to **R2** > **Overview**
3. Copy your **Account ID**
4. Create a new bucket or use an existing one
5. Generate R2 API tokens:
   - Go to **R2** > **Manage R2 API Tokens**
   - Click **Create API Token**
   - Give it a name and appropriate permissions
   - Copy the **Access Key ID** and **Secret Access Key**

```env
R2_ACCOUNT_ID=your-account-id
R2_ACCESS_KEY=your-access-key
R2_SECRET_KEY=your-secret-key
R2_BUCKET_NAME=your-bucket-name
R2_PUBLIC_URL=https://pub-your-hash.r2.dev
```

The public URL format is: `https://pub-<bucket-hash>.r2.dev`

You can find this in your R2 bucket settings under "Public URL".

#### CORS Configuration

For development, you can use:
```env
ALLOWED_ORIGINS=*
```

For production, specify exact origins:
```env
ALLOWED_ORIGINS=https://yourdomain.com,https://app.yourdomain.com
```

## Step 4: Create the Database

If using a local PostgreSQL instance, create the database:

```bash
mix ecto.create
```

If using a hosted database, ensure the database already exists or create it through your hosting provider's dashboard.

## Step 5: Run Database Migrations

Apply all database migrations:

```bash
mix ecto.migrate
```

This will create all necessary tables, indexes, and triggers for:
- Users and authentication
- Videos and engagement (likes, comments, shares)
- Channels
- Posts
- Video Reactions Chat (WebSocket-based messaging)
- Wallet and transactions
- Calls and call history
- Contacts, blocking, and privacy settings

## Step 6: Load Environment Variables

The application needs to load environment variables before starting. You have two options:

**Option A: Manual export (Linux/macOS)**
```bash
export $(cat .env | xargs)
mix phx.server
```

**Option B: Windows**
```bash
# Load each variable manually, or use a tool like 'dotenv'
set DB_HOST=your-host
set DB_PORT=25060
# ... etc
mix phx.server
```

**Option C: Use a .env loader (Recommended)**

Install `dotenv` for Elixir:

Add to `mix.exs`:
```elixir
{:dotenv, "~> 3.0.0", only: [:dev, :test]}
```

Then run:
```bash
mix deps.get
```

The environment variables will be loaded automatically when you run `mix phx.server`.

## Step 7: Start the Development Server

Start the Phoenix server:

```bash
mix phx.server
```

Or start it inside IEx (Interactive Elixir) for debugging:

```bash
iex -S mix phx.server
```

The server should start at: **http://localhost:4000**

## Step 8: Verify the Setup

Test that the server is running correctly:

```bash
curl http://localhost:4000/api/v1/health
```

You should see a health check response indicating the database connection is working.

## Common Issues & Troubleshooting

### Database Connection Errors

**Error: "connection refused"**
- Ensure PostgreSQL is running: `pg_ctl status` (local) or check your hosting provider
- Verify `DB_HOST` and `DB_PORT` are correct
- Check firewall rules if using a hosted database

**Error: "authentication failed"**
- Double-check `DB_USER` and `DB_PASSWORD` in `.env`
- Ensure the user has proper permissions on the database

**Error: "too many connections"**
- Reduce `DB_POOL_SIZE` in `.env` (try 3 for development)
- Close other connections to the database
- Restart any zombie Phoenix server processes

### Firebase Errors

**Error: "invalid credentials"**
- Verify `FIREBASE_CREDENTIALS_PATH` points to the correct JSON file
- Ensure the JSON file has proper permissions (readable)
- Confirm the service account has **Firebase Admin SDK** permissions

**Error: "project not found"**
- Check that `FIREBASE_PROJECT_ID` matches your Firebase project
- Ensure the service account belongs to the correct project

### Cloudflare R2 Errors

**Error: "access denied"**
- Verify `R2_ACCESS_KEY` and `R2_SECRET_KEY` are correct
- Ensure the API token has proper permissions (read/write to the bucket)
- Check that `R2_BUCKET_NAME` matches exactly (case-sensitive)

**Error: "bucket not found"**
- Confirm the bucket exists in your R2 dashboard
- Verify `R2_ACCOUNT_ID` is correct

### Port Already in Use

**Error: `:eaddrinuse` - Port 4000 already in use**

Find and kill the process:

**Windows:**
```bash
netstat -ano | findstr :4000
taskkill /PID <process-id> /F
```

**Linux/macOS:**
```bash
lsof -i :4000
kill -9 <process-id>
```

### Environment Variables Not Loading

If environment variables aren't being loaded:

1. Verify `.env` file exists in the root directory
2. Check for syntax errors in `.env` (no spaces around `=`)
3. Ensure you're running from the correct directory
4. Try manually exporting variables to test

## Development Workflow

### Running Migrations

Create a new migration:
```bash
mix ecto.gen.migration create_my_table
```

Apply migrations:
```bash
mix ecto.migrate
```

Rollback last migration:
```bash
mix ecto.rollback
```

### Database Console

Open a database console:
```bash
mix ecto.psql
```

### Code Formatting

Format all code:
```bash
mix format
```

### Testing (when tests are added)

Run tests:
```bash
mix test
```

Run tests with coverage:
```bash
mix test --cover
```

## Security Reminders

- **NEVER** commit `.env` to version control
- **NEVER** commit Firebase service account JSON files
- **ALWAYS** use `.env.example` as a template for new environments
- **ALWAYS** generate a new `SECRET_KEY_BASE` for each environment
- **NEVER** share credentials in Slack, email, or other unsecured channels
- **ALWAYS** use environment-specific credentials (dev vs. staging vs. production)

## Additional Resources

- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix/)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [Firebase Admin SDK Setup](https://firebase.google.com/docs/admin/setup)
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)

## Getting Help

If you encounter issues:

1. Check the logs in the terminal where `mix phx.server` is running
2. Review this SETUP.md guide
3. Check the project's issue tracker
4. Ask the team for assistance

## Next Steps

After setup is complete:

1. Review the [CLAUDE.md](./CLAUDE.md) file for project architecture details
2. Explore the API endpoints in the router files
3. Start implementing new features or fixing bugs
4. Run the development server and test the API

Happy coding!
