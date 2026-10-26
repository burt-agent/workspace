# repository-smoke

A tiny **integration smoke project** for the `burt-agent/workspace`
repository and the burt_bot coding tools (read, test, publish).

This is **not** the dictionary client. It exists only to prove, end to end,
that a branch can be read, a complete project bundle can be tested offline in
the sandbox, and the tested bundle can be published back to the repository.

## Contents

- `lib/Arith.pm` — one function: `add($x, $y)`.
- `t/arith.t` — assertions covering positive, zero and negative inputs,
  plus float cases and a commutativity cross-check.

## Running the tests

```sh
perl -Ilib t/arith.t
```

Expected final line: `Result: PASS` (with `Files=1`).

## Requirements

Core Perl only, plus `Test::More` from the standard distribution. No network,
no dependencies, no credentials.

## License

Same terms as Perl itself.
