AS = as
ASFLAGS = --64
LD = ld

all: qafc

qafc.o: qaf.s
	$(AS) $(ASFLAGS) qaf.s -o qafc.o

qafc: qafc.o
	$(LD) -o qafc qafc.o

TEST_FILES = fib.qf fact.qf primes.qf collatz.qf \
	test_arithmetic.qf test_char_io.qf test_comparisons.qf test_input.qf \
	test_logical.qf test_loop_control.qf test_print.qf test_strings.qf \
	test_while.qf test_import.qf test_import_all.qf test_import_multi.qf \
	test_jit.qf test_features.qf test_types.qf demo.qf body.qf

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

.PHONY: all test clean
