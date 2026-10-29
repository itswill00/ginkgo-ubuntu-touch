.PHONY: all check shellcheck syntax deviceinfo overlay clean help

SHELL := /bin/bash
SCRIPTS := $(wildcard scripts/*.sh)
INSTALLER := flashable_zips/update-binary.template.sh

help:
	@echo "make check       - run every consistency check (what CI runs)"
	@echo "make shellcheck  - lint shell"
	@echo "make syntax      - bash -n on every script"
	@echo "make deviceinfo  - verify deviceinfo parses and has the required keys"
	@echo "make overlay     - verify the overlay is consistent"
	@echo "make clean       - remove build products"

check: syntax shellcheck deviceinfo overlay
	@echo
	@echo "RESULT: all checks passed"

syntax:
	@echo "==> shell syntax"
	@for f in $(SCRIPTS) $(INSTALLER); do \
		bash -n "$$f" || { echo "    syntax error in $$f"; exit 1; }; \
	done
	@echo "    ok"

shellcheck:
	@echo "==> shellcheck"
	@command -v shellcheck >/dev/null || { echo "    shellcheck not installed"; exit 1; }
	@shellcheck -S info $(SCRIPTS) $(INSTALLER)
	@echo "    no findings"

deviceinfo:
	@echo "==> deviceinfo"
	@bash -c 'set -e; source ./deviceinfo; \
		for k in deviceinfo_name deviceinfo_codename deviceinfo_arch \
		         deviceinfo_kernel_source deviceinfo_kernel_source_branch \
		         deviceinfo_kernel_defconfig deviceinfo_kernel_cmdline \
		         deviceinfo_halium_version deviceinfo_ubuntu_touch_release; do \
			[ -n "$${!k}" ] || { echo "    missing: $$k"; exit 1; }; \
		done; \
		[ "$$deviceinfo_codename" = "ginkgo" ] || { echo "    codename is not ginkgo"; exit 1; }; \
		[ "$$deviceinfo_halium_version" = "10" ] || { echo "    halium version is not 10"; exit 1; }; \
		case "$$deviceinfo_kernel_cmdline" in \
			*console=tty0*) ;; \
			*) echo "    cmdline is missing console=tty0"; exit 1;; \
		esac'
	@echo "    ok"

overlay:
	@python3 scripts/check_overlay.py

clean:
	rm -rf out dist build-workspace
	@echo "cleaned"
