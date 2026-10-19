# R18 query benchmark

Measured on 2026-10-08 using an isolated copy of the 2026-10-06 catalog: 1,909,835 videos, 9,522,662 category links, and 2,488,692 actress links.

All 31 public DBR18 methods execute successfully across 96 scenarios (94 SQL executions, including chunked bulk lookups). Fixtures check list/count consistency, cast modes, duplicates, matching-version metadata, pagination, and the SQLite 999-parameter ceiling. All 60 targeted Flutter tests pass; analyzer and Python migration/import checks pass.

## Measurement

- Before: one SQL run per scenario; previous Explore optimization is already included. Three statements exceeded the 30-second limit.
- After: median of three SQL runs per statement. Multiple statements in one scenario are summed. Times include fetching SQL rows, excluding Dart JSON transport, object conversion, and UI rendering.
- Cached Advanced Search scenarios issue no SQL.
- Nine important statements were replayed with native macOS SQLite 3.51.0; result hashes matched the Python SQLite worker.
- Fresh catalog preparation: 44.77 seconds, database size 3.13 → 3.74 GiB, `PRAGMA quick_check = ok`. Repeated preparation: 0.18 seconds. Setup ran alongside validation, so its timing is indicative.

## Changes

- Prepare Advanced Search summaries once per immutable snapshot, transactionally with rollback/retry.
- Add covering and partial indexes; use constant blacklist predicates to enable those partial indexes.
- Fetch the page before joining metadata; aggregate category and actress links independently.
- Scan translated-title matches before joining videos; index numeric year-prefix ranges.
- Use correlated relation checks for paginated lists and video-code-filtered counts.
- Match all Series IDs with the same LIKE semantics in list and count queries.
- Chunk bulk lookups below SQLite parameter limits.

## Remaining costs

Broad substring searches still scan catalog or translation data. Actress count for `a` still takes about four seconds; Series wildcard queries with single/multi-cast filtering take about one second. Large dictionaries incur transport and rendering costs beyond SQL time. No new search semantics or FTS dependency was introduced.

Rich metadata now has deterministic latest-row tie selection; GROUP_CONCAT ordering is not an API guarantee. Fixture regressions preserve eligibility and matching-version metadata.

## Reproduce

```sh
flutter test test/r18_queries_test.dart

# Preparation writes to this disposable copy.
cp -c /path/to/r18.db /tmp/r18-benchmark.db
python3 -B assets/python/r18_importer.py --indexes-only /tmp/r18-benchmark.db
R18_BENCHMARK_DB=/tmp/r18-benchmark.db R18_BENCHMARK_REPORT=/tmp/r18-report.json R18_BENCHMARK_RUNS=3 flutter test test/r18_queries_test.dart --reporter expanded
```

The real-database harness defaults to sample code ABP-099; override `R18_BENCHMARK_CODE` if needed. It reads the prepared database without modifying it.

## Every scenario

| Scenario | Before SQL ms (1 run) | After SQL ms (median of 3) |
| --- | ---: | ---: |
| `getCountAllVideos` | 14.33 | 1.59 |
| `getVideo` | 50.30 | 6.18 |
| `getPosterByCodes` | 0.06 | 0.02 |
| `getPosterByCodes.large` | — | 0.51 |
| `getActress` | 0.79 | 0.03 |
| `getCategory` | 0.53 | 0.02 |
| `getCategoriesByVideoCodes` | 0.07 | 0.02 |
| `getCategoriesByVideoCodes.large` | — | 0.49 |
| `getDirector` | 0.18 | 0.02 |
| `getAllActress` | 331.25 | 281.81 |
| `getAllActress.search` | 224.69 | 220.08 |
| `getAllCategories` | 4.30 | 0.70 |
| `getAllCategories.search` | 0.48 | 0.38 |
| `getAllSeries` | 136.55 | 110.05 |
| `getAllSeries.search` | 98.88 | 99.39 |
| `search.ABP-099` | 3,972.05 | 1,198.82 |
| `getSearchCount.ABP-099` | 3,001.20 | 853.97 |
| `search.ABP099` | 2,564.58 | 971.69 |
| `getSearchCount.ABP099` | 3,633.89 | 836.82 |
| `search.Old` | 20,593.28 | 1,018.50 |
| `getSearchCount.Old` | 18,279.64 | 1,042.89 |
| `search.` | >30,000 (timeout) | 2.78 |
| `getSearchCount.` | >30,000 (timeout) | 184.37 |
| `getByFilter.false` | >30,000 (timeout) | 2.45 |
| `getByFilterCount.false` | 3,921.58 | 174.10 |
| `getByFilter.true` | 8,772.57 | 7.99 |
| `getByFilterCount.true` | 184.30 | 173.18 |
| `getByFilter.actress` | — | 6.59 |
| `getByFilterCount.actress` | — | 3,986.94 |
| `getByFilter.combined` | — | 691.04 |
| `getByFilterCount.combined` | — | 537.90 |
| `getNewRelease` | 421.83 | 5.71 |
| `getAdvancedSearchGroups.Series` | 585.98 | 213.43 |
| `getAdvancedSearchGroups.Series.cachedSearch` | — | cached |
| `getAdvancedSearchVideos.Series` | 184.13 | 1.04 |
| `getAdvancedSearchVideos.Series.missing` | — | 0.29 |
| `getAdvancedSearchGroups.Category` | 6,674.32 | 1.95 |
| `getAdvancedSearchGroups.Category.cachedSearch` | — | cached |
| `getAdvancedSearchVideos.Category` | 930.35 | 394.16 |
| `getAdvancedSearchVideos.Category.missing` | — | 0.06 |
| `getAdvancedSearchGroups.Actress` | 2,613.89 | 297.23 |
| `getAdvancedSearchGroups.Actress.cachedSearch` | — | cached |
| `getAdvancedSearchVideos.Actress` | 224.57 | 7.48 |
| `getAdvancedSearchVideos.Actress.missing` | — | 0.02 |
| `getAdvancedSearchGroups.Year` | 1,275.55 | 0.11 |
| `getAdvancedSearchGroups.Year.cachedSearch` | — | cached |
| `getAdvancedSearchVideos.Year` | 9,920.43 | 0.31 |
| `getAdvancedSearchVideos.Year.missing` | — | 0.22 |
| `getAllVideosByActress.all` | 143.95 | 7.70 |
| `getCountAllVideosByActress.all` | 9.70 | 5.76 |
| `getAllVideosByCategory.all` | 240.29 | 173.02 |
| `getCountAllVideosByCategory.all` | 163.48 | 153.58 |
| `getAllVideosBySeries.all` | 6,884.31 | 4.86 |
| `getCountAllVideosBySeries.all` | 1.16 | 4.61 |
| `getAllVideosBySeriesWildcard.all` | 7,280.45 | 450.76 |
| `getCountAllVideosBySeriesWildcard.all` | 6,126.04 | 365.31 |
| `getAllVideosByLabel.all` | 16.92 | 9.31 |
| `getCountAllVideosByLabel.all` | 6.44 | 6.03 |
| `getAllVideosByStudio.all` | 111.88 | 89.35 |
| `getCountAllVideosByStudio.all` | 77.96 | 78.04 |
| `getAllVideosByDirector.all` | 23.74 | 2.95 |
| `getCountAllVideosByDirector.all` | 2.43 | 1.62 |
| `getAllVideosByYear.all` | 259.03 | 51.65 |
| `getCountAllVideosByYear.all` | 281.11 | 32.50 |
| `getAllVideosByActress.single` | 276.12 | 16.72 |
| `getCountAllVideosByActress.single` | 34.97 | 13.04 |
| `getAllVideosByCategory.single` | 304.28 | 217.47 |
| `getCountAllVideosByCategory.single` | 197.08 | 187.07 |
| `getAllVideosBySeries.single` | 6,475.08 | 5.34 |
| `getCountAllVideosBySeries.single` | 1.35 | 4.92 |
| `getAllVideosBySeriesWildcard.single` | 5,970.99 | 1,207.71 |
| `getCountAllVideosBySeriesWildcard.single` | 6,389.34 | 1,181.21 |
| `getAllVideosByLabel.single` | 20.33 | 17.46 |
| `getCountAllVideosByLabel.single` | 8.71 | 14.58 |
| `getAllVideosByStudio.single` | 122.98 | 110.60 |
| `getCountAllVideosByStudio.single` | 91.67 | 93.02 |
| `getAllVideosByDirector.single` | 26.08 | 4.18 |
| `getCountAllVideosByDirector.single` | 2.94 | 2.20 |
| `getAllVideosByYear.single` | 425.57 | 180.46 |
| `getCountAllVideosByYear.single` | 304.19 | 158.72 |
| `getAllVideosByActress.multi` | 125.43 | 14.48 |
| `getCountAllVideosByActress.multi` | 16.27 | 10.84 |
| `getAllVideosByCategory.multi` | 265.67 | 238.03 |
| `getCountAllVideosByCategory.multi` | 205.20 | 183.14 |
| `getAllVideosBySeries.multi` | 5,752.70 | 4.99 |
| `getCountAllVideosBySeries.multi` | 2.56 | 4.48 |
| `getAllVideosBySeriesWildcard.multi` | 6,018.51 | 1,106.64 |
| `getCountAllVideosBySeriesWildcard.multi` | 6,206.24 | 1,240.91 |
| `getAllVideosByLabel.multi` | 22.55 | 7.57 |
| `getCountAllVideosByLabel.multi` | 13.31 | 7.78 |
| `getAllVideosByStudio.multi` | 191.63 | 112.86 |
| `getCountAllVideosByStudio.multi` | 96.99 | 97.22 |
| `getAllVideosByDirector.multi` | 31.17 | 3.66 |
| `getCountAllVideosByDirector.multi` | 2.39 | 1.88 |
| `getAllVideosByYear.multi` | 553.83 | 188.29 |
| `getCountAllVideosByYear.multi` | 431.21 | 154.29 |
