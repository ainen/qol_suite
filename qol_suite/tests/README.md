# Test coverage

CI tests gen1recomp v0.1.91 and v0.1.92 and runs every `*_test.lua` file
directly. It then repeats the RBY compatibility suite with
`QOL_SUITE_TEST_VERSION` set to `red`, `blue`, and `yellow`, and requires the
Gold suite to execute without skipping.

Development checkouts that include the modkit graph runner can also run the
contract with the values strategy. The complete option Cartesian product is
intentionally too large; focused behavioral tests and explicit parent/child
scenarios cover the important interactions instead:

```text
python3 tools/modkit.py test ../qol_suite --base fixture --headless-only \
  --graph-strategy values
```

That development graph runner models the RBY settings schema. Gold-only rows
are covered by the non-skipping Gold suites instead of being declared as RBY
contract options.
