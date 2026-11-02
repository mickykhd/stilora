-- Down migration for 0000_faulty_xavin
-- Drops every table created by the up migration (CASCADE resolves FK order)
-- and the enum types. The runner-managed `hush_migrations` table is untouched.
DROP TABLE IF EXISTS "accounts" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "activity" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "attachments" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "channel_members" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "channels" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "invites" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "messages" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "notification_prefs" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "pins" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "reactions" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "sessions" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "users" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "verifications" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "workspace_members" CASCADE;--> statement-breakpoint
DROP TABLE IF EXISTS "workspaces" CASCADE;--> statement-breakpoint
DROP TYPE IF EXISTS "channel_kind" CASCADE;--> statement-breakpoint
DROP TYPE IF EXISTS "workspace_role" CASCADE;
