ALTER TABLE derived_video ADD COLUMN video_code TEXT;

WITH
  widths AS (
    SELECT upper(substr(trim(dvd_id), 1, instr(trim(dvd_id), '-') - 1)) AS prefix,
      min(length(substr(trim(dvd_id), instr(trim(dvd_id), '-') + 1))) AS width
    FROM derived_video
    WHERE instr(trim(dvd_id), '-') > 2
      AND substr(trim(dvd_id), instr(trim(dvd_id), '-') + 1) NOT GLOB '*[^0-9]*'
      AND length(substr(trim(dvd_id), instr(trim(dvd_id), '-') + 1)) BETWEEN 2 AND 5
    GROUP BY prefix
  ),
  cores AS (
    SELECT rowid AS id,
      ltrim(CASE WHEN lower(content_id) LIKE 'h\_%' ESCAPE '\' OR lower(content_id) LIKE 'n\_%' ESCAPE '\'
        THEN substr(content_id, 3) ELSE content_id END, '0123456789_') AS core
    FROM derived_video
    WHERE nullif(trim(dvd_id), '') IS NULL AND service_code IN ('digital', 'mono')
  ),
  parts AS (
    SELECT id, upper(rtrim(core, '0123456789')) AS prefix,
      substr(core, length(rtrim(core, '0123456789')) + 1) AS serial
    FROM cores
  ),
  -- ponytail: unknown families use three digits, ambiguous suffix variants stay unresolved.
  codes AS (
    SELECT id, p.prefix || '-' || printf('%0*d', coalesce(w.width, 3), cast(p.serial AS INTEGER)) AS code
    FROM parts p LEFT JOIN widths w ON w.prefix = p.prefix
    WHERE length(p.prefix) >= 2 AND p.prefix NOT GLOB '*[^A-Z]*'
      AND p.serial != '' AND p.serial NOT GLOB '*[^0-9]*'
      AND length(coalesce(nullif(ltrim(p.serial, '0'), ''), '0')) <= 5
  )
UPDATE derived_video SET video_code = coalesce(nullif(upper(trim(dvd_id)), ''),
  (SELECT code FROM codes WHERE codes.id = derived_video.rowid));

CREATE INDEX idx_derived_video_code ON derived_video(video_code, content_id, title_en);
CREATE INDEX idx_dv_advanced_codes ON derived_video(series_id, video_code, release_date, content_id) WHERE
      length(substr(video_code, 1, instr(video_code, '-') - 1)) >= 2 AND substr(video_code, 1, instr(video_code, '-') - 1) NOT GLOB '*[^A-Za-z]*'
      AND length(ltrim((CASE WHEN instr(substr(video_code, instr(video_code, '-') + 1), '-') = 0 THEN substr(video_code, instr(video_code, '-') + 1) ELSE substr(substr(video_code, instr(video_code, '-') + 1), 1, instr(substr(video_code, instr(video_code, '-') + 1), '-') - 1) END), 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')) BETWEEN 2 AND 5
      AND ltrim((CASE WHEN instr(substr(video_code, instr(video_code, '-') + 1), '-') = 0 THEN substr(video_code, instr(video_code, '-') + 1) ELSE substr(substr(video_code, instr(video_code, '-') + 1), 1, instr(substr(video_code, instr(video_code, '-') + 1), '-') - 1) END), 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz') NOT GLOB '*[^0-9]*'
      AND (CASE WHEN instr(substr(video_code, instr(video_code, '-') + 1), '-') = 0 THEN 'x' ELSE substr(substr(video_code, instr(video_code, '-') + 1), instr(substr(video_code, instr(video_code, '-') + 1), '-') + 1) END) != '' AND (CASE WHEN instr(substr(video_code, instr(video_code, '-') + 1), '-') = 0 THEN 'x' ELSE substr(substr(video_code, instr(video_code, '-') + 1), instr(substr(video_code, instr(video_code, '-') + 1), '-') + 1) END) NOT GLOB '*[^A-Za-z0-9]*'
     AND video_code NOT LIKE 'TK%' AND video_code NOT LIKE '7%' AND video_code NOT LIKE '9%' AND video_code NOT LIKE 'K9%' AND video_code NOT LIKE 'FTKT%' AND video_code NOT LIKE 'GOOE%' AND video_code NOT LIKE 'JTKT%' AND video_code NOT LIKE 'GTKT%' AND video_code NOT LIKE 'DDMP%' AND video_code NOT LIKE 'DMPXA%' AND video_code NOT LIKE 'USTD%' AND video_code NOT LIKE 'VWBS%' AND video_code NOT LIKE 'HPXR%' AND video_code NOT LIKE 'VWAS%' AND video_code NOT LIKE 'TCBD%' AND video_code NOT LIKE 'DAXA%' AND video_code NOT LIKE 'TWUSS%' AND video_code NOT LIKE 'PJXF%' AND video_code NOT LIKE 'KKC%' AND video_code NOT LIKE 'GNXF%' AND video_code NOT LIKE 'JAXA%' AND video_code NOT LIKE 'UHB%' AND video_code NOT LIKE 'BPUH%' AND video_code NOT LIKE 'GNXT%' AND video_code NOT LIKE 'ZTKT%' AND video_code NOT LIKE 'PB%' AND video_code NOT LIKE 'D1%' AND video_code NOT LIKE 'D2%' AND video_code NOT LIKE 'D3%' AND video_code NOT LIKE 'DK%' AND video_code NOT LIKE 'BCQA%' AND video_code NOT LIKE 'ANRS%' AND video_code NOT LIKE 'SPUF%' AND video_code NOT LIKE 'ANRM%' AND video_code NOT LIKE '%BOD' AND video_code NOT LIKE '%DOD' AND video_code NOT LIKE '%Ta' AND video_code NOT LIKE '%Tb' AND video_code NOT LIKE '%Tc' AND video_code NOT LIKE '%Td' AND video_code NOT LIKE '%Te' AND video_code NOT LIKE '%TK' AND video_code NOT LIKE '%TK1' AND video_code NOT LIKE '%TK2' AND video_code NOT LIKE '%TK3' AND video_code NOT LIKE '%EC' AND video_code NOT LIKE '%4D' AND video_code NOT LIKE '%5D' AND video_code NOT LIKE '%DL';
ANALYZE idx_derived_video_code;
ANALYZE idx_dv_advanced_codes;
