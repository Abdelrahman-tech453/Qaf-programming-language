# Imports & modules

Longer programs split across files. Qaf's module system is deliberately
simple: a module is just another `.qf` file, and importing it **registers its
function definitions** without executing any top-level statements.

## Three forms

```qf
# 1. Bring in every function the module defines
from stdlib import *;

# 2. Bring in only named functions
from math import gcd, fact;

# 3. Whole-module import (equivalent to `from math import *`)
import math;
```

## Rules

* The module name is a file name: `stdlib` resolves to `stdlib.qf`.
* `from m import a, b;` — `a` and `b` must be function names the module
  defines; importing a name the module does not define raises
  `qaf: imported name not found: a`.
* Imported names land in the global function table, exactly as if the
  functions had been defined in your file — so call them directly:
  `print gcd(48, 18);`
* Imports nest: an imported module may itself `import` other modules, and
  imports are processed depth-first.
* Circular imports are safely ignored (a module already being processed is
  skipped, much like an include guard).
* Only **functions** are shared. Global variables set at top level of a
  module are not exported, and imported modules never run statements, so
  importing cannot have side effects.

## Resolution order

When your program says `from some_name import ...`, the runtime looks for
`some_name.qf` in these places, in order:

| # | Location | Typical use |
|---|----------|-------------|
| 1 | current working directory | your project's local modules |
| 2 | directory of the top-level program file | modules living next to the program |
| 3 | directory containing the `qafc` binary | a qafc that ships companion modules |
| 4 | **`<qafc dir>/lib`** | running qafc straight from the repository (`./lib`) |
| 5 | **`<parent of qafc dir>/lib/qaf`** | an installed copy (`$prefix/bin/qafc` + `$prefix/lib/qaf`) |

Each location is tried with the module name as-is and with a `.qf` suffix.
The first hit wins. Together, roots 4 and 5 mean `from stdlib import *` and
`from math import *` work from **any** directory — whether you run the
repository's `./qafc` or an installed `qaf` from `$prefix/bin`.

## Installing

`./install.sh` builds, tests, and installs `qafc` + the `qaf` command to
`$prefix/bin`, puts the standard library in `$prefix/lib/qaf` (found by
root 5 above), and the examples in `$prefix/share/qaf/examples`. Imports then
resolve no matter where you invoke `qaf` from.

## Writing a module

Just a file of `fn` definitions — and keep it side-effect-free so imports are
safe:

```qf
# geometry.qf              <- your module
fn area_of_square(s) { return s * s; }
fn area_of_circle(r) { return 3.14159 * r * r; }
```

```qf
# main.qf
from geometry import area_of_square;
print area_of_square(4);     # 16
```

Run it from anywhere and it works, because directory #2 is the program's own
directory:

```bash
cd /elsewhere
./qafc ~/proj/main.qf
```

## Example layout in this repo

```
lib/         stdlib.qf, math.qf          (resolvable from anywhere)
examples/    demo, fib, perceptron, ...  each imports from lib/ or from a
           sibling file in the same folder
tests/       the test programs
```

`examples/perceptron.qf` performs `from math import *` and
`examples/demo.qf` performs `from stdlib import *`, so the examples double as
living demonstrations of the import system.