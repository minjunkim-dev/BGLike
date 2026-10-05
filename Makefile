SHELL := /bin/bash

.PHONY: check repository-check godot-install godot-check
check: repository-check godot-check

repository-check:
	git diff --check
	python3 -m unittest discover -s scripts -p 'test_*.py'

godot-install:
	bash scripts/install_godot.sh

godot-check:
	bash scripts/check_godot.sh
