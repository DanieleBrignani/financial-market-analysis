.PHONY: setup test run offline refresh clean all

all: test run

setup:
	Rscript scripts/setup.R

test:
	Rscript tests/testthat.R

run:
	Rscript scripts/run_analysis.R

offline:
	Rscript scripts/run_analysis.R --offline

refresh:
	Rscript scripts/run_analysis.R --refresh

clean:
	rm -f output/figures/*.png output/tables/*.csv output/tables/*.txt
