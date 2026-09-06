AS = as
ASFLAGS = --64 -I src
LD = ld

PREFIX ?= /usr/local
DESTDIR ?=
INSTALL = install

all: qafc

qafc.o: src/qaf.s src/defs.s src/bss.s src/data.s src/syscalls.s \
	src/lexer.s src/parser.s src/imports.s src/eval.s src/runtime.s \
	src/jit.s src/repl.s src/main.s
	$(AS) $(ASFLAGS) src/qaf.s -o qafc.o

qafc: qafc.o
	$(LD) -o qafc qafc.o

TEST_FILES = examples/fib.qf examples/fact.qf examples/primes.qf examples/collatz.qf \
	tests/test_arithmetic.qf tests/test_char_io.qf tests/test_comparisons.qf tests/test_input.qf \
	tests/test_logical.qf tests/test_loop_control.qf tests/test_print.qf tests/test_strings.qf \
	tests/test_while.qf tests/test_import.qf tests/test_import_all.qf tests/test_import_multi.qf \
	tests/test_jit.qf tests/test_features.qf tests/test_types.qf examples/demo.qf examples/body.qf \
	examples/tui_menu.qf examples/tui_calculator.qf

test: qafc
	@for f in $(TEST_FILES); do \
		echo "Running $$f (jit)..."; \
		./qafc $$f > /dev/null || exit 1; \
		echo "Running $$f (nojit)..."; \
		./qafc $$f nojit > /dev/null || exit 1; \
	done
	@echo "All tests passed successfully!"

clean:
	rm -f qafc qafc.o

# ------------------------------------------------------------------ install --
# Installs qafc, the `qaf` command, the standard library and the examples.
# The installed binary looks for the standard library in two places:
#   * <exe dir>/lib              (dev layout; matches ./lib)
#   * <parent of exe dir>/lib/qaf (the layout below, i.e. $PREFIX/lib/qaf)
# so the copies in $PREFIX, $PREFIX/bin, $PREFIX/share are all self-contained.
install: qafc
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/bin \
		$(DESTDIR)$(PREFIX)/lib/qaf \
		$(DESTDIR)$(PREFIX)/share/qaf/examples \
		$(DESTDIR)$(PREFIX)/share/doc/qaf/docs
	$(INSTALL) -m 0755 qafc $(DESTDIR)$(PREFIX)/bin/qafc
	ln -sf qafc $(DESTDIR)$(PREFIX)/bin/qaf
	$(INSTALL) -m 0644 lib/*.qf $(DESTDIR)$(PREFIX)/lib/qaf/
	cp -r examples/. $(DESTDIR)$(PREFIX)/share/qaf/examples/
	$(INSTALL) -m 0644 README.md LICENSE $(DESTDIR)$(PREFIX)/share/doc/qaf/
	cp -r docs/. $(DESTDIR)$(PREFIX)/share/doc/qaf/docs/
	@echo "Qaf installed to $(DESTDIR)$(PREFIX) (run 'qaf' or '$(DESTDIR)$(PREFIX)/bin/qafc')"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/qafc $(DESTDIR)$(PREFIX)/bin/qaf
	rm -rf $(DESTDIR)$(PREFIX)/lib/qaf \
		$(DESTDIR)$(PREFIX)/share/qaf \
		$(DESTDIR)$(PREFIX)/share/doc/qaf

.PHONY: all test clean install uninstall
