# ADR 003: Persistence Architecture & Database Engine Choice

## Status
Accepted

## Context
NetGet currently stores tasks in a monolithic JSON file (`netget_tasks.json`) and settings in `netget_settings.json`.
Key problems with this approach:
1. Full-list serialization on every checkpoint: every progress checkpoint rewrites the entire task array, creating high I/O churn and flash wear on mobile devices.
2. Sudden process termination during file writing risks truncating or corrupting the JSON payload.
3. State omission: named queues, schedules, speed mode, per-task pause reasons, and elapsed seconds are held in in-memory Maps and lost across process restarts.
4. Phase 3 features (Data Budget `usage_ledger`, mirror URLs, queue scheduling) require structured, relational queries.

## Decision
We replace the JSON file persistence with an **ACID-compliant SQLite database**:
1. **Engine Selection:** `sqflite` (with WAL mode enabled). It provides robust native Android SQLite integration, minimal binary overhead, and direct SQL transaction control without code-generation complexity.
2. **Schema Design:**
   - `tasks`: Core task attributes, typed failure codes, pause reasons, resume metrics, integrity status, and headers.
   - `segments`: Granular segment checkpoint records (`task_id`, `segment_index`, `start_byte`, `end_byte`, `downloaded_bytes`, `is_completed`).
   - `queues`: Named queues with concurrency limits and network policies.
   - `schedules`: Automated time windows (`start_hour`, `start_minute`, `stop_hour`, `stop_minute`).
   - `usage_ledger`: Daily traffic ledger by network type (`day`, `network_type`, `counted_bytes`, `free_bytes`) for data budget tracking.
   - `mirrors`: Alternative URLs and failover states per task.
3. **Data Safety & Migration:**
   - During initial initialization, NetGet checks for legacy `netget_tasks.json` and `netget_settings.json`.
   - Existing tasks are parsed and migrated into SQLite.
   - A backup copy (`netget_tasks.json.bak`) is preserved. The original file is not deleted.
   - Database corruption handling: if opening fails, the database is backed up to `netget.db.corrupt-<timestamp>` and a fresh database is created with a non-blocking user notification.

## Consequences
- **Positive:** Atomic checkpoints: active downloads update only their specific task and segment rows.
- **Positive:** Zero data loss on abrupt termination or battery death.
- **Positive:** Persistent named queues, schedules, data budget ledger, and pause reasons.
- **Positive:** High performance with thousands of historical items.
