SHELL := /bin/bash

.PHONY: check repository-check godot-install godot-check
check: repository-check godot-check

repository-check:
	python3 scripts/check_whitespace.py
	python3 scripts/check_bugbot_rules.py
	python3 -m unittest discover -s scripts -p 'test_*.py'

godot-install:
	bash scripts/install_godot.sh

godot-check:
	bash scripts/check_godot.sh
