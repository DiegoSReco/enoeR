# enoeR (development version)

## New features

* `enoe_list()`: Retrieve the full catalogue of available ENOE quarters.
  Returns a `data.frame` with columns `year`, `quarter`, `survey` (ENOE /
  ENOE-N), and `url`, covering 2005 Q1 through the latest published period.
  Useful for inspecting coverage before calling `enoe_load()`.

* `enoe_metadata()`: Access variable-level metadata for any ENOE module.
  Returns a `data.frame` with `variable`, `label`, `type`, and `module`
  columns sourced from the official INEGI data dictionary. Accepts a `module`
  argument (`"sdem"`, `"coe1t"`, etc.) and an optional `lang` argument
  (`"es"` / `"en"`) for label language.

# enoeR 0.1.0

## New features

* `enoe_load()`: Download a single quarter. Supports all five ENOE modules
  (`sdem`, `coe1t`, `coe2t`, `hog`, `viv`) with automatic URL resolution for
  ENOE (2005–2020 Q1), ENOE-N (2020 Q3–2022 Q4), and ENOE (2023+).
