#!/bin/bash
# Proposal: dark neutrals shifted toward amber (canvas #1A1816, card #272320, input #13110F, muted #B8AFA3).
set -euo pipefail
F=Ortus/Views/OrtusTheme.swift
sed -i '' \
  -e 's/red: 0.10, green: 0.10, blue: 0.11/red: 0.102, green: 0.094, blue: 0.086/' \
  -e 's/red: 0.16, green: 0.16, blue: 0.18/red: 0.153, green: 0.137, blue: 0.125/' \
  -e 's/red: 0.08, green: 0.08, blue: 0.09/red: 0.075, green: 0.067, blue: 0.059/' \
  -e 's/red: 0.72, green: 0.70, blue: 0.66/red: 0.722, green: 0.686, blue: 0.639/' "$F"
