import os
import sqlite3
import re
import time
import datetime

def convert_sql_to_sqlite_fast(sql_file_path, sqlite_db_path):
    conn = None
    try:
        print(f"🚀 Mulai impor: '{sql_file_path}' → '{sqlite_db_path}'")

        print("📊 Menghitung total baris...")
        with open(sql_file_path, 'r', encoding='utf-8') as f:
            total_lines_estimate = sum(1 for _ in f)
        print(f"📏 Total baris dalam file: {total_lines_estimate:,}\n")

        start_time = time.time()

        conn = sqlite3.connect(sqlite_db_path)
        cursor = conn.cursor()

        conn.execute('PRAGMA synchronous = OFF;')
        conn.execute('PRAGMA journal_mode = MEMORY;')
        conn.execute('PRAGMA locking_mode = EXCLUSIVE;')
        conn.execute('PRAGMA temp_store = 2;')
        conn.execute('PRAGMA cache_size = 1000000;')
        conn.execute('PRAGMA page_size = 65536;')
        conn.execute('PRAGMA foreign_keys = OFF;')

        conn.execute('BEGIN TRANSACTION;')

        total_statements = 0
        skipped_pg_statements = 0
        converted_copy_statements = 0
        total_lines = 0
        error_count = 0

        current_statement_parts = []
        copy_blocks = []

        copy_regex = re.compile(r"COPY\s+(?:public\.)?(\w+)\s*\((.*?)\)\s+FROM\s+stdin;", re.IGNORECASE)
        pg_prefixes = (
            "SET ", "SELECT PG_CATALOG.", "CREATE EXTENSION ", "ALTER DEFAULT PRIVILEGES",
            "REVOKE ", "GRANT ", "COMMENT ON ", "CREATE SEQUENCE ", "ALTER SEQUENCE ",
            "DO $$", "BEGIN;", "COMMIT;", "TRUNCATE ONLY ", "DROP TABLE IF EXISTS ONLY ",
            "DROP VIEW IF EXISTS ONLY ", "ALTER TABLE ONLY public.", "SEQUENCE NAME",
            "START WITH ", "INCREMENT BY ", "NO MINVALUE", "NO MAXVALUE", "CACHE ",
            "CREATE INDEX ",
        )

        def execute_sql_statement(sql_stmt, line_number):
            nonlocal total_statements, error_count
            sql_stmt = sql_stmt.strip()
            if not sql_stmt or sql_stmt in ('()', ')', '('):
                return
            if re.match(r'INSERT INTO\s+\w+\s*\(\s*\)\s*VALUES\s*\(\s*\)', sql_stmt, re.IGNORECASE):
                return
            if re.match(r'ALTER TABLE\s+\w+\s+ADD CONSTRAINT\s+\w+\s+PRIMARY KEY\s*\(.*\)', sql_stmt, re.IGNORECASE):
                return
            if re.match(r'ADD CONSTRAINT\s+\w+\s+PRIMARY KEY\s*\(.*\)', sql_stmt, re.IGNORECASE):
                return

            sql_stmt = re.sub(r"public\.", "", sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'\s+USING\s+btree\s*', ' ', sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'timestamp with time zone', 'DATETIME', sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'character varying(\(\d+\))?', 'TEXT', sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'\bdate\b', 'TEXT', sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'(\s+INTEGER\s+NOT NULL)\s+GENERATED ALWAYS AS IDENTITY\s*\([^)]*\)', r'\1 PRIMARY KEY AUTOINCREMENT', sql_stmt, flags=re.IGNORECASE)
            sql_stmt = re.sub(r'(\s+INTEGER)\s+GENERATED ALWAYS AS IDENTITY\s*\([^)]*\)', r'\1 PRIMARY KEY AUTOINCREMENT', sql_stmt, flags=re.IGNORECASE)

            try:
                cursor.execute(sql_stmt)
                total_statements += 1
            except Exception as e:
                error_count += 1
                print(f"⚠️ Error [line {line_number}] {type(e).__name__}: {e}")
                print(f"📝 Statement: {sql_stmt[:300]}...")

        with open(sql_file_path, 'r', encoding='utf-8') as f:
            in_copy_block = False
            copy_table = ""
            copy_columns = []
            copy_lines = []

            for line_num, line in enumerate(f, 1):
                total_lines += 1
                line = line.strip()

                if total_lines % 500000 == 0:
                    elapsed = time.time() - start_time
                    percent = (total_lines / total_lines_estimate) * 100
                    speed = total_lines / elapsed
                    remaining = (total_lines_estimate - total_lines) / speed if speed else 0
                    eta = datetime.timedelta(seconds=int(remaining))
                    print(f"🔄 {total_lines:,} baris ({percent:.2f}%) • {speed:,.0f} baris/detik • ETA: {eta}")

                if in_copy_block:
                    if line == r"\.":
                        copy_blocks.append((copy_table, copy_columns, copy_lines.copy()))
                        copy_lines.clear()
                        in_copy_block = False
                        continue
                    else:
                        copy_lines.append(line)
                        continue

                line = re.sub(r'--.*$', '', line)
                line = re.sub(r'/\*.*?\*/', '', line, flags=re.DOTALL).strip()
                if not line:
                    continue

                match = copy_regex.match(line)
                if match:
                    copy_table = match.group(1)
                    copy_columns = [col.strip() for col in match.group(2).split(',')]
                    in_copy_block = True
                    continue

                if any(line.upper().startswith(p.upper()) for p in pg_prefixes):
                    skipped_pg_statements += 1
                    current_statement_parts = []
                    continue

                current_statement_parts.append(line)
                if line.endswith(';') and not re.search(r"'.*;'", line):
                    full_stmt = " ".join(current_statement_parts).rstrip(';')
                    execute_sql_statement(full_stmt, line_num)
                    current_statement_parts = []

        for table_name, columns, lines in copy_blocks:
            # Patch nama kolom jika SQLite mengubah otomatis
            sqlite_column_aliases = {
                "release_date": "release_date",
                "timestamp": "timestamp",
            }
            adjusted_columns = [sqlite_column_aliases.get(col.strip('"'), col.strip('"')) for col in columns]


            cursor.execute(f"PRAGMA table_info({table_name})")
            existing_cols = [row[1] for row in cursor.fetchall()]
            if not set(adjusted_columns).issubset(set(existing_cols)):
                print(f"⚠️  Lewati COPY ke {table_name}: kolom tidak cocok → {adjusted_columns} ≠ {existing_cols}")
                continue

            if columns != adjusted_columns:
                print(f"🔧 Patched kolom untuk {table_name}: {columns} → {adjusted_columns}")

            placeholders = ', '.join(['?'] * len(adjusted_columns))
            insert_sql = f"INSERT INTO {table_name} ({', '.join(adjusted_columns)}) VALUES ({placeholders})"
            batch = []
            for line in lines:
                values = line.split('\t')
                parsed = [None if v == r'\N' or v.lower() == 'infinity' else v for v in values]
                batch.append(parsed)
            cursor.executemany(insert_sql, batch)
            total_statements += len(batch)
            converted_copy_statements += len(batch)

        conn.execute('COMMIT;')

        print("⚙️  Membuat index untuk akselerasi query...")
        index_statements = [
            # Index untuk video
            "CREATE INDEX IF NOT EXISTS idx_derived_video_dvd_id ON derived_video(dvd_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_content_id ON derived_video(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_title_ja ON derived_video(title_ja);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_release_date ON derived_video(release_date);",

            # Relasi maker, label, series, site
            "CREATE INDEX IF NOT EXISTS idx_derived_video_maker_id ON derived_video(maker_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_label_id ON derived_video(label_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_series_id ON derived_video(series_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_site_id ON derived_video(site_id);",

            # machine_translation
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_source_ja ON machine_translation(source_ja);",
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_target_en ON machine_translation(target_en);",
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_timestamp ON machine_translation(timestamp);",

            # derived_maker/label/series/site names
            "CREATE INDEX IF NOT EXISTS idx_label_name_en ON derived_label(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_maker_name_ja ON derived_maker(name_ja);",
            "CREATE INDEX IF NOT EXISTS idx_series_name_en ON derived_series(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_site_name ON derived_site(name);",

            # actress
            "CREATE INDEX IF NOT EXISTS idx_video_actress_content_id ON derived_video_actress(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_actress_actress_id ON derived_video_actress(actress_id);",
            "CREATE INDEX IF NOT EXISTS idx_actress_id ON derived_actress(id);",
            "CREATE INDEX IF NOT EXISTS idx_actress_name ON derived_actress(name_romaji);",

            # actor
            "CREATE INDEX IF NOT EXISTS idx_video_actor_content_id ON derived_video_actor(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_actor_actor_id ON derived_video_actor(actor_id);",
            "CREATE INDEX IF NOT EXISTS idx_actor_id ON derived_actor(id);",

            # director
            "CREATE INDEX IF NOT EXISTS idx_video_director_content_id ON derived_video_director(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_director_director_id ON derived_video_director(director_id);",
            "CREATE INDEX IF NOT EXISTS idx_director_id ON derived_director(id);",

            # category
            "CREATE INDEX IF NOT EXISTS idx_video_category_content_id ON derived_video_category(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_category_category_id ON derived_video_category(category_id);",
            "CREATE INDEX IF NOT EXISTS idx_category_id ON derived_category(id);",
            "CREATE INDEX IF NOT EXISTS idx_category_name_en ON derived_category(name_en);",

            # timestamp extras
            "CREATE INDEX IF NOT EXISTS idx_dmm_trailer_timestamp ON source_dmm_trailer(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_dmm_video_histrion_timestamp ON source_dmm_video_histrion(timestamp);",
        ]


        for stmt in index_statements:
            try: cursor.execute(stmt)
            except Exception as e: print(f"⚠️ Gagal membuat index: {stmt} → {e}")

        duration = datetime.timedelta(seconds=int(time.time() - start_time))

        print("\n✅ SELESAI!")
        print(f"📄 Total baris dibaca     : {total_lines:,}")
        print(f"🧾 Statement dieksekusi   : {total_statements:,}")
        print(f"📅 INSERT dari COPY       : {converted_copy_statements:,}")
        print(f"⏭️ PG baris dilewati      : {skipped_pg_statements:,}")
        print(f"❌ Error eksekusi         : {error_count:,}")
        print(f"⏱️ Durasi eksekusi        : {duration}")

    except Exception as e:
        import traceback
        print(f"🚨 Fatal error: {e}")
        traceback.print_exc()
    finally:
        if conn:
            conn.close()
            print("🔌 Koneksi SQLite ditutup.")

if __name__ == "__main__":
    try: os.remove('new_r18_ultrafast.db')
    except: pass

    input_sql_file = 'r18dotdev_dump_2025-07-15.sql'
    output_sqlite_db = 'new_r18_ultrafast.db'
    convert_sql_to_sqlite_fast(input_sql_file, output_sqlite_db)
