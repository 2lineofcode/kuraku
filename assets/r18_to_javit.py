import argparse
import glob
import os
import sqlite3
import re
import time
import datetime
from pathlib import Path


SCRIPT_NAME = "r18_to_javit"
SCRIPT_VERSION = "1.3.0"
SCRIPT_UPDATED_AT = "2026-10-01"


def create_video_codes(conn):
    if any(row[1] == 'video_code' for row in conn.execute('PRAGMA table_info(derived_video)')):
        return
    script = Path(__file__).with_name('r18_video_codes.sql').read_text()
    with conn:
        if not conn.in_transaction:
            conn.execute('BEGIN')
        for statement in script.split(';'):
            if statement.strip():
                conn.execute(statement)


def create_catalog_indexes(conn):
    create_video_codes(conn)
    conn.execute('CREATE INDEX IF NOT EXISTS idx_dvc_content_category ON derived_video_category(content_id, category_id)')
    conn.execute('ANALYZE idx_dv_advanced_codes')
    conn.execute('ANALYZE derived_video_category')


def cleanup_old_r18_dbs(workdir, keep_db_path):
    keep_abs = os.path.abspath(keep_db_path)
    for db_path in glob.glob(os.path.join(workdir, "r18*.db")):
        abs_path = os.path.abspath(db_path)
        if abs_path == keep_abs:
            continue
        try:
            os.remove(abs_path)
            print(f"🧹 Removed old DB: {abs_path}")
        except Exception as e:
            print(f"⚠️ Failed removing old DB: {abs_path} | {e}")


def cleanup_source_files(input_sql_file):
    try:
        if os.path.exists(input_sql_file):
            os.remove(input_sql_file)
            print(f"🧹 Removed source SQL: {input_sql_file}")
    except Exception as e:
        print(f"⚠️ Failed removing source SQL: {input_sql_file} | {e}")

    gz_path = f"{input_sql_file}.gz"
    try:
        if os.path.exists(gz_path):
            os.remove(gz_path)
            print(f"🧹 Removed source GZ: {gz_path}")
    except Exception as e:
        print(f"⚠️ Failed removing source GZ: {gz_path} | {e}")

# tested : 00:01:20 ~ 00:02:00
def psql2sqlite(in_psql_file, out_sqlite_file):
    conn = None
    try:
        print(f"🚀 Mulai impor: '{in_psql_file}' → '{out_sqlite_file}'")

        start_time = time.time()

        conn = sqlite3.connect(out_sqlite_file)
        cursor = conn.cursor()

        # ===============================
        # 🔥 PRAGMA KOMPATIBEL + AMAN
        # ===============================
        conn.execute('PRAGMA synchronous = OFF;')               # Matikan flush disk
        conn.execute('PRAGMA journal_mode = OFF;')              # Matikan journal sama sekali
        conn.execute('PRAGMA locking_mode = EXCLUSIVE;')        # Full lock, single writer
        conn.execute('PRAGMA temp_store = MEMORY;')             # Temp di RAM
        conn.execute('PRAGMA cache_size = -1048576;')           # ~1GB cache (page-based)
        conn.execute('PRAGMA page_size = 65536;')               # Max page size (64KB)
        conn.execute('PRAGMA mmap_size = 281474976710656;')     # Max mmap size (256 TB teoritis)
        conn.execute('PRAGMA foreign_keys = OFF;')              # Matikan cek foreign key
        conn.execute('PRAGMA automatic_index = OFF;')           # Matikan index otomatis
        conn.execute('PRAGMA count_changes = OFF;')             # Matikan update counter

        conn.execute("BEGIN;")

        total_lines = 0
        total_statements = 0
        total_copy_rows = 0
        skipped_pg = 0
        error_count = 0

        copy_regex = re.compile(r"COPY\s+(?:public\.)?(\w+)\s*\((.*?)\)\s+FROM\s+stdin;", re.IGNORECASE)

        pg_skip_prefixes = (
            "SET ",
            "SELECT PG_CATALOG.",
            "CREATE EXTENSION",
            "ALTER DEFAULT PRIVILEGES",
            "REVOKE ",
            "GRANT ",
            "COMMENT ON ",
            "CREATE SEQUENCE",
            "ALTER SEQUENCE",
            "SEQUENCE NAME",
            "START WITH",
            "INCREMENT BY",
            "NO MINVALUE",
            "NO MAXVALUE",
            "CACHE",
            "DO $$",
            "BEGIN;",
            "COMMIT;",
            "TRUNCATE ONLY",
            "DROP TABLE IF EXISTS ONLY",
            "DROP VIEW IF EXISTS ONLY",
            "ALTER TABLE",
            "ADD CONSTRAINT",
            "CREATE INDEX",
        )

        in_copy = False
        copy_table = None
        copy_columns = None
        insert_sql = None
        batch = []
        batch_size = 200_000  # 🔥 lebih kecil tapi stabil

        stmt_parts = []

        with open(in_psql_file, "r", encoding="utf-8") as f:
            for line_no, raw_line in enumerate(f, 1):
                total_lines += 1
                line = raw_line.strip()

                if total_lines % 500_000 == 0:
                    elapsed = time.time() - start_time
                    speed = total_lines / elapsed
                    print(f"🔄 {total_lines:,} lines • {speed:,.0f} lines/sec")

                # ===============================
                # COPY MODE
                # ===============================
                if in_copy:
                    if line == r"\.":
                        if batch:
                            cursor.executemany(insert_sql, batch)
                            total_copy_rows += len(batch)
                            batch.clear()

                        print(f"📦 COPY {copy_table}: {total_copy_rows:,} rows")
                        in_copy = False
                        continue

                    values = raw_line.rstrip("\n").split("\t")
                    parsed = [None if v == r"\N" else v for v in values]
                    batch.append(parsed)

                    if len(batch) >= batch_size:
                        cursor.executemany(insert_sql, batch)
                        total_copy_rows += len(batch)
                        batch.clear()

                    continue

                # ===============================
                # NORMAL MODE
                # ===============================
                if not line or line.startswith("--"):
                    continue

                if any(line.upper().startswith(p) for p in pg_skip_prefixes):
                    skipped_pg += 1
                    stmt_parts.clear()
                    continue

                match = copy_regex.match(line)
                if match:
                    copy_table = match.group(1)
                    copy_columns = [c.strip().strip('"') for c in match.group(2).split(",")]
                    placeholders = ", ".join(["?"] * len(copy_columns))
                    insert_sql = f"""
                        INSERT INTO {copy_table}
                        ({', '.join(copy_columns)})
                        VALUES ({placeholders})
                    """
                    in_copy = True
                    batch.clear()
                    continue

                stmt_parts.append(line)
                if line.endswith(";") and not re.search(r"'.*;'", line):
                    stmt = " ".join(stmt_parts).rstrip(";")
                    stmt_parts.clear()

                    if stmt in ("", "(", ")", "()"):
                        continue

                    # 🔥 JANGAN HAPUS AUTOINCREMENT
                    stmt = stmt.replace("public.", "").replace("USING btree", " ")
                    stmt = re.sub(r'timestamp with time zone', 'DATETIME', stmt, flags=re.IGNORECASE)
                    stmt = re.sub(r'character varying(\(\d+\))?', 'TEXT', stmt, flags=re.IGNORECASE)
                    stmt = re.sub(r'\bdate\b', 'TEXT', stmt, flags=re.IGNORECASE)

                    try:
                        cursor.execute(stmt)
                        total_statements += 1
                    except Exception as e:
                        error_count += 1
                        print(f"⚠️ SQL error [line {line_no}]: {e}")

        conn.commit()

        # ===============================
        # 🔥 INDEX MINIMAL & AMAN
        # ===============================
        print("⚙️ Membuat index penting saja...")

        safe_indexes = [
            # Video - Basic
            "CREATE INDEX IF NOT EXISTS idx_derived_video_content_id ON derived_video(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_title_en ON derived_video(title_en);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_title_ja ON derived_video(title_ja);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_release_date ON derived_video(release_date);",
            
            # Video - Composite (Meng-cover dvd_id dan series_id)
            "CREATE INDEX IF NOT EXISTS idx_derived_video_dvd_id_title_en ON derived_video (dvd_id, title_en);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_dvd_id ON derived_video(dvd_id);",
            "CREATE INDEX IF NOT EXISTS idx_dv_series_release_desc ON derived_video(series_id, release_date DESC);",
            "CREATE INDEX IF NOT EXISTS idx_dv_series_id_release_date ON derived_video (series_id, release_date);",
            "CREATE INDEX IF NOT EXISTS idx_dv_release_date_content ON derived_video(release_date, content_id);",

            # Relations
            "CREATE INDEX IF NOT EXISTS idx_derived_video_maker_id_release_date ON derived_video (maker_id, release_date DESC);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_maker_id ON derived_video(maker_id);", # Keep if used without release_date frequently
            "CREATE INDEX IF NOT EXISTS idx_derived_video_label_id ON derived_video(label_id);",
            "CREATE INDEX IF NOT EXISTS idx_derived_video_site_id ON derived_video(site_id);",

            # Entities (Series, Maker, Label, Director, Site)
            "CREATE INDEX IF NOT EXISTS idx_ds_name_en_id ON derived_series (name_en, id);",
            "CREATE INDEX IF NOT EXISTS idx_label_name_en ON derived_label(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_maker_name_ja ON derived_maker(name_ja);",
            "CREATE INDEX IF NOT EXISTS idx_derived_maker_name_en ON derived_maker(name_en);",
            "CREATE INDEX IF NOT EXISTS idx_site_name ON derived_site(name);",
            "CREATE INDEX IF NOT EXISTS idx_derived_director_name_romaji ON derived_director(name_romaji);",
            "CREATE INDEX IF NOT EXISTS idx_derived_director_name_kana ON derived_director(name_kana);",
            "CREATE INDEX IF NOT EXISTS idx_director_id ON derived_director(id);",
            "CREATE INDEX IF NOT EXISTS idx_dvd_director_content_id ON derived_video_director(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_dvd_director_director_id ON derived_video_director(director_id);",

            # Actress & Actor
            "CREATE INDEX IF NOT EXISTS idx_dva_composite_content_actress ON derived_video_actress (content_id, actress_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_actress_actress_id ON derived_video_actress(actress_id);",
            "CREATE INDEX IF NOT EXISTS idx_actress_id ON derived_actress(id);",
            "CREATE INDEX IF NOT EXISTS idx_actress_name ON derived_actress(name_romaji);",
            "CREATE INDEX IF NOT EXISTS idx_video_actor_content_id ON derived_video_actor(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_actor_actor_id ON derived_video_actor(actor_id);",
            "CREATE INDEX IF NOT EXISTS idx_actor_id ON derived_actor(id);",

            # Category
            "CREATE INDEX IF NOT EXISTS idx_dvc_category_content ON derived_video_category(category_id, content_id);",
            "CREATE INDEX IF NOT EXISTS idx_video_category_content_id ON derived_video_category(content_id);",
            "CREATE INDEX IF NOT EXISTS idx_category_id ON derived_category(id);",
            "CREATE INDEX IF NOT EXISTS idx_dc_name_id ON derived_category(name_en, id);",

            # Others & Translation
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_source_ja ON machine_translation(source_ja);",
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_target_en ON machine_translation(target_en);",
            "CREATE INDEX IF NOT EXISTS idx_machine_translation_timestamp ON machine_translation(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_dmm_trailer_timestamp ON source_dmm_trailer(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_dmm_video_histrion_timestamp ON source_dmm_video_histrion(timestamp);"
        ]

        for stmt in safe_indexes:
            cursor.execute(stmt)

        create_catalog_indexes(conn)
        conn.commit()
        cursor.execute("PRAGMA optimize;")

        duration = datetime.timedelta(seconds=int(time.time() - start_time))

        print("\n✅ SELESAI!")
        print(f"📄 Total baris dibaca     : {total_lines:,}")
        print(f"🧾 Statement dieksekusi   : {total_statements:,}")
        print(f"📦 INSERT dari COPY       : {total_copy_rows:,}")
        print(f"⏭️ PG baris dilewati      : {skipped_pg:,}")
        print(f"❌ Error eksekusi         : {error_count:,}")
        print(f"⏱️ Durasi eksekusi        : {duration}")

    finally:
        if conn:
            conn.close()
            print("🔌 Koneksi SQLite ditutup.")



if __name__ == "__main__":
    print(f"🧩 {SCRIPT_NAME} v{SCRIPT_VERSION} ({SCRIPT_UPDATED_AT})")

    parser = argparse.ArgumentParser(description="PSQL to SQLite converter")
    parser.add_argument(
        "-d", "--dir",
        default=".",
        help="Working directory (default: current directory)"
    )
    parser.add_argument('--indexes-only', metavar='DATABASE', help='Add catalog indexes to an existing SQLite database without importing or deleting files')
    args = parser.parse_args()
    if args.indexes_only:
        conn = sqlite3.connect(Path(args.indexes_only).resolve().as_uri() + '?mode=rw', uri=True, timeout=30)
        try:
            create_catalog_indexes(conn)
            conn.commit()
            print('Catalog indexes ready')
        finally:
            conn.close()
        raise SystemExit(0)

    workdir = args.dir

    files = glob.glob(os.path.join(workdir, "r18*.sql"))

    if len(files) == 0:
        print(f"No SQL file found in {workdir}")
        exit(1)

    input_sql_file = files[0]
    now = datetime.datetime.now().strftime("%Y_%m_%d")
    
    match = re.search(r'\d{4}-\d{2}-\d{2}', input_sql_file)
    if match:
        version = match.group(0).replace('-', '_')
    else:
        version = now

    output_sqlite_db = os.path.join(workdir, f"r18_{version}.db")

    print(f"Input SQL: {input_sql_file}")
    print(f"Output DB: {output_sqlite_db}")
    print(f"Target DB Version Tag: {version}")

    cleanup_old_r18_dbs(workdir, output_sqlite_db)
    psql2sqlite(input_sql_file, output_sqlite_db)
    cleanup_source_files(input_sql_file)
