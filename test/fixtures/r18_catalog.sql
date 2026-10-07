CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, series_id INTEGER, release_date TEXT, title_en TEXT, title_ja TEXT, runtime_mins INTEGER, sample_url TEXT, jacket_full_url TEXT, jacket_thumb_url TEXT, service_code TEXT DEFAULT 'digital', maker_id INTEGER DEFAULT 1, label_id INTEGER DEFAULT 1, site_id INTEGER DEFAULT 1, gallery_full_first TEXT, gallery_full_last TEXT);
CREATE TABLE derived_maker(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_label(id INTEGER, name_en TEXT);
CREATE TABLE derived_site(id INTEGER, name TEXT);
CREATE TABLE derived_director(id INTEGER, name_romaji TEXT, name_kana TEXT);
CREATE TABLE derived_video_director(content_id TEXT, director_id INTEGER);
INSERT INTO derived_maker VALUES (1,'Studio',NULL);
INSERT INTO derived_label VALUES (1,'Label');
INSERT INTO derived_site VALUES (1,'FANZA');
INSERT INTO derived_director VALUES (1,'Director',NULL);
CREATE TABLE derived_series(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_category(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_actress(id INTEGER, name_romaji TEXT, name_kanji TEXT, name_kana TEXT);
CREATE TABLE derived_video_category(content_id TEXT, category_id INTEGER);
CREATE TABLE derived_video_actress(content_id TEXT, actress_id INTEGER);
CREATE TABLE machine_translation(source_ja TEXT, target_en TEXT);
INSERT INTO derived_series VALUES (1, 'Cast', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_category VALUES (1, 'Cast', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_actress VALUES (1, '', '日本語', 'かな'), (2, 'Same name', NULL, NULL), (3, 'Same name', NULL, NULL), (4, 'Empty', NULL, NULL);
INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,title_ja,runtime_mins,sample_url,jacket_full_url,jacket_thumb_url) VALUES
 ('a', 'ABC-123', 1, '2026-01-01', '', '日本語', 120, '', '', ''),
 ('b', 'ABC-124', 2, '2020-01-01', 'Old', '', 60, '', '', ''),
 ('c', 'ABC-125', 1, NULL, 'Unknown date', '', 30, '', '', ''),
 ('d', 'TK-123', 3, '2030-01-01', 'Blocked', '', 30, '', '', ''),
 ('e', 'INVALID', 3, '2030-01-01', 'Invalid', '', 30, '', '', '');
INSERT INTO derived_video_category VALUES ('a',1),('b',2),('c',1),('d',3),('e',3);
INSERT INTO derived_video_actress VALUES ('a',1),('a',2),('b',3),('c',1),('c',1),('d',4),('e',4);
INSERT INTO derived_video_director VALUES ('a',1),('b',1),('c',1);
INSERT INTO machine_translation VALUES ('日本語','Translated title');
