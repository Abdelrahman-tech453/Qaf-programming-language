# Qaf quick reference

The complete syntax of the language on one page. Every keyword, operator, and
construct. Run with `./qafc file.qf` (or `nojit` for the interpreter, or no
argument for the REPL).

## Program structure

```
program     := import* statement*
statement   := print expr ';'
             | 'if' '(' expr ')' block ('else' 'if' '(' expr ')' block)* ('else' block)?
             | 'while' '(' expr ')' block
             | block
             | 'break' ';' | 'continue' ';'
             | 'fn' name '(' name (',' name)* ')' block
             | 'return' expr? ';'
             | expr ';'
             | import-statement
import-stmt := 'from' name 'import' '*' ';'
             | 'from' name 'import' name (',' name)* ';'
             | 'import' name ';'
block       := '{' statement* '}'
```

## Keywords (all 17)

```
fn     return   if    else   while
print  break    continue
var    let
read   putchar  getchar
from   import
true   false
```

## Literals & values

```
123        integer (64-bit signed)
3.14       float  (IEEE-754 double)
"text"     string (escapes: \n \t \r \0 \\ \")
true       boolean
false      boolean
list(x,...)  list; list() is empty
```

## Variables

```
x = expr;      # create or reassign a mutable variable
var x = 5;     # explicitly mutable
let x = 5;     # immutable; reassignment is a runtime error
```

## Operators (precedence, high -> low)

```
- !                     unary          (right)
* / %                   multiplicative  (left)
+ -                     additive        (left)
< > <= >=               relational      (left)
== !=                   equality        (left)
&&                      logical and     (left, short-circuit)
||                      logical or      (left, short-circuit)
=                       assignment
```

Note: `+` on two strings means concatenation.

## Expressions

```
expr := literal
      | identifier
      | '(' expr ')'
      | '-' expr | '!' expr
      | expr op expr            (ops above)
      | expr '[' expr ']'       indexing: list -> element, string -> 1-char str
      | name '(' args ')'       function call / builtin call
      | assignment: identifier '=' expr
```

Statements and expressions are separated by `;`. Blocks use `{ }`. List
indexing and assignment: `xs[i]` reads, `xs[i] = v` writes (lists only; strings
are immutable).

## Built-in functions

```
list(...)      make a list         len(x)       size of str/list
push(l,x)      append              pop(l)       remove & return last
type(x)        tag: 0 int, 1 float, 2 bool, 3 str, 4 list

int2str(n)    float2str(f)   str2int(s)    str2float(s)
int2float(n)  float2int(f)   bool2int(b)   int2bool(n)

concat(a,b)   str + str          char(n)    codepoint -> 1-char string
str_get(s,i)  char at index      str_set(s,i,c)  new string with char replaced
floor(f)  sqrt(f)  exp(f)  log(f)
```

## Input / output

```
print expr;    # value + newline
read();        # read one integer from stdin
getchar();     # one byte, or -1 at EOF
putchar(c);    # write one byte
```

## Imports

```
from stdlib import *;                  # all of a module's functions
from math import gcd, fact;            # named functions
import math;                           # the whole module
```

Search order: current dir → program's dir → qafc's dir → `<qafc dir>/lib`.

## Errors

Runtime errors begin with `qaf:` and report the offending source line:
`qaf: at line N: message` in the interpreter, and the plain message under the
JIT. Common ones:

```
qaf: division by zero
qaf: index out of bounds
qaf: pop from empty list
qaf: cannot assign to immutable variable
qaf: stack overflow (too deep recursion)
qaf: unknown function: name
```

## Limits

```
source 64 KiB | 256 identifiers | 64 functions | 8 parameters
256 stack frames | 16384 tokens | 16384 AST nodes | 4 MiB JIT arena
```

Full walkthrough: [The Qaf guide](guide.md).