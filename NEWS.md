# enoeR (development version)

# enoeR 0.1.0

## New features

* `enoe_load()`: Download a single quarter. Supports all five ENOE modules
  (`sdem`, `coe1t`, `coe2t`, `hog`, `viv`) with automatic URL resolution for
  ENOE (2005–2020 Q1), ENOE-N (2020 Q3–2022 Q4), and ENOE (2023+).

* `enoe_list()`: Batch download across a range of years and quarters.
  Includes retry logic (`retry_times`, `retry_wait`), automatic exclusion of
  the ETOE 2020 Q2 period, and an `enoe_meta` attribute with download metadata.

* `enoe_extract()`: Pull one named table from every quarter in a panel list.

* `enoe_stack()`: Row-bind one table across all quarters into a single
  `data.table` with an optional `period` identifier column.

* `enoe_meta()`: Pretty-print download metadata from a panel object.
