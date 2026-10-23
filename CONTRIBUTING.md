# Contributing

Submit changes through a pull request from a fork. A committer listed in
`CODEOWNERS` merges after explicit approval. Reference relevant issues; discuss
non-Solderpad licenses before contributing.

## Commits

- Keep patches atomic and logically ordered, without merge commits or fixup series.
  Rebase or squash before review; do not force-push.
- Prefer a square-bracketed area tag, such as `[uart]` or `[hw/vendor]`, at the
  start of area-specific subjects.
- Use imperative, capitalized subjects, at most 100 characters, without a final period.
- Separate the body with a blank line; explain what changed and why.

## Style

Follow surrounding code and these conventions:

- RTL: [lowRISC SystemVerilog](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).
- C/C++: [Google style](https://google.github.io/styleguide/cppguide.html) and the repository formatter configuration.
- Python: [PEP 8](https://www.python.org/dev/peps/pep-0008/).
- YAML: `ymlfmt`.
