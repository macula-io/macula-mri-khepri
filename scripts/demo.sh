#!/bin/bash
# Launch the Proximus Network TUI Demo
# Usage: ./scripts/demo.sh

set -e
cd "$(dirname "$0")/.."

echo "Starting Macula MRI - Proximus Demo..."
echo ""

# Compile first
rebar3 compile

echo ""
echo "╭────────────────────────────────────────────────────────────╮"
echo "│  Type this command to start the demo:                     │"
echo "│                                                            │"
echo "│    macula_mri_khepri_tui:start().                         │"
echo "│                                                            │"
echo "│  Press Ctrl+G then 'q' to exit the shell when done.       │"
echo "╰────────────────────────────────────────────────────────────╯"
echo ""

# Run shell with a distributed node name (required for Ra/Khepri)
exec rebar3 shell --sname mri_demo
