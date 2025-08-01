#!/bin/bash

# Ensure script is run from the project root
directory=$(dirname "$0")
cd "$directory"

# Run the application with RUST_LOG for debugging MAC verification failures
RUST_LOG=debug cargo run
