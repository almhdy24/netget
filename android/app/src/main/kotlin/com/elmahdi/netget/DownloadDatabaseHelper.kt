package com.elmahdi.netget

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DownloadDatabaseHelper(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_NAME = "netget_native.db"
        const val DATABASE_VERSION = 1

        const val TABLE_TASKS = "tasks"
        const val COL_ID = "id"
        const val COL_URL = "url"
        const val COL_FILE_NAME = "file_name"
        const val COL_SAVE_PATH = "save_path"
        const val COL_TOTAL_BYTES = "total_bytes"
        const val COL_DOWNLOADED_BYTES = "downloaded_bytes"
        const val COL_STATUS = "status"
        const val COL_SPEED = "speed"
        const val COL_RESUMABLE = "resumable"
        const val COL_CATEGORY = "category"
        const val COL_CONNECTIONS = "connections"
        const val COL_ETAG = "etag"
        const val COL_LAST_MODIFIED = "last_modified"
        const val COL_REFERRER = "referrer"
        const val COL_QUEUE_NAME = "queue_name"
        const val COL_CREATED_AT = "created_at"
        const val COL_COMPLETED_AT = "completed_at"
        const val COL_ELAPSED_SECONDS = "elapsed_seconds"

        const val TABLE_SEGMENTS = "segments"
        const val COL_SEG_TASK_ID = "task_id"
        const val COL_SEG_INDEX = "seg_index"
        const val COL_SEG_START = "start_byte"
        const val COL_SEG_END = "end_byte"
        const val COL_SEG_DOWNLOADED = "downloaded_bytes"
        const val COL_SEG_COMPLETED = "is_completed"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_TASKS (
                $COL_ID TEXT PRIMARY KEY,
                $COL_URL TEXT NOT NULL,
                $COL_FILE_NAME TEXT NOT NULL,
                $COL_SAVE_PATH TEXT NOT NULL,
                $COL_TOTAL_BYTES INTEGER NOT NULL DEFAULT -1,
                $COL_DOWNLOADED_BYTES INTEGER NOT NULL DEFAULT 0,
                $COL_STATUS TEXT NOT NULL,
                $COL_SPEED REAL NOT NULL DEFAULT 0.0,
                $COL_RESUMABLE INTEGER NOT NULL DEFAULT 1,
                $COL_CATEGORY TEXT NOT NULL DEFAULT 'other',
                $COL_CONNECTIONS INTEGER NOT NULL DEFAULT 4,
                $COL_ETAG TEXT,
                $COL_LAST_MODIFIED TEXT,
                $COL_REFERRER TEXT,
                $COL_QUEUE_NAME TEXT NOT NULL DEFAULT 'Main',
                $COL_CREATED_AT INTEGER NOT NULL,
                $COL_COMPLETED_AT INTEGER,
                $COL_ELAPSED_SECONDS INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE $TABLE_SEGMENTS (
                $COL_SEG_TASK_ID TEXT NOT NULL,
                $COL_SEG_INDEX INTEGER NOT NULL,
                $COL_SEG_START INTEGER NOT NULL,
                $COL_SEG_END INTEGER NOT NULL,
                $COL_SEG_DOWNLOADED INTEGER NOT NULL DEFAULT 0,
                $COL_SEG_COMPLETED INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY ($COL_SEG_TASK_ID, $COL_SEG_INDEX)
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE_SEGMENTS")
        db.execSQL("DROP TABLE IF EXISTS $TABLE_TASKS")
        onCreate(db)
    }

    fun upsertTask(taskValues: ContentValues) {
        writableDatabase.insertWithOnConflict(
            TABLE_TASKS,
            null,
            taskValues,
            SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun updateProgress(id: String, downloaded: Long, speed: Double, elapsed: Int) {
        val cv = ContentValues().apply {
            put(COL_DOWNLOADED_BYTES, downloaded)
            put(COL_SPEED, speed)
            put(COL_ELAPSED_SECONDS, elapsed)
        }
        writableDatabase.update(TABLE_TASKS, cv, "$COL_ID = ?", arrayOf(id))
    }

    fun updateStatus(id: String, status: String, completedAt: Long? = null) {
        val cv = ContentValues().apply {
            put(COL_STATUS, status)
            if (completedAt != null) {
                put(COL_COMPLETED_AT, completedAt)
            }
        }
        writableDatabase.update(TABLE_TASKS, cv, "$COL_ID = ?", arrayOf(id))
    }

    fun deleteTask(id: String) {
        writableDatabase.delete(TABLE_SEGMENTS, "$COL_SEG_TASK_ID = ?", arrayOf(id))
        writableDatabase.delete(TABLE_TASKS, "$COL_ID = ?", arrayOf(id))
    }
}
