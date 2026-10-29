#!/bin/bash
# Halfway: the same greys with only a hint of warmth (canvas #1B1A19, card #2A2826, input #141312).
set -euo pipefail
F=Ortus/Views/OrtusTheme.swift
sed -i '' \
  -e 's/red: 0.10, green: 0.10, blue: 0.11/red: 0.106, green: 0.102, blue: 0.098/' \
  -e 's/red: 0.16, green: 0.16, blue: 0.18/red: 0.165, green: 0.157, blue: 0.149/' \
  -e 's/red: 0.08, green: 0.08, blue: 0.09/red: 0.078, green: 0.075, blue: 0.071/' "$F"
