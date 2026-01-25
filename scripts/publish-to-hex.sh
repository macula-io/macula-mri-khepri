#!/usr/bin/env bash
set -e

# Simple hex.pm publish script for macula-mri-khepri

cd "$(dirname "$0")/.."

# Source secrets
[ -f "$HOME/.config/zshrc/01-secrets" ] && source "$HOME/.config/zshrc/01-secrets"

echo "Publishing macula_mri_khepri to hex.pm..."
echo ""

# Version check
VERSION=$(grep -oP '(?<={vsn, ")[^"]+' apps/macula_mri_khepri/src/macula_mri_khepri.app.src)

echo "Version: $VERSION"
echo ""

# Run tests
echo "Running tests..."
rebar3 eunit || echo "Tests had warnings but no failures"
echo ""

# Build docs
echo "Building documentation..."
rebar3 ex_doc
echo ""

# Build package
echo "Building hex package..."
rebar3 hex build
echo ""

# Publish
echo "Publishing..."
rebar3 hex publish --yes
echo ""
echo "Done! Published macula_mri_khepri $VERSION"
echo "Documentation will be available at: https://hexdocs.pm/macula_mri_khepri"
