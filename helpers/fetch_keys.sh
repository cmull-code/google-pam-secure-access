#!/bin/bash
# Query GitHub for the user's public SSH keys
USERNAME=$1

# Safety: Allow only alphanumeric/dashes (prevents injection)
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then exit 1; fi

# Fetch from GitHub
curl -s --connect-timeout 5 "https://github.com/${USERNAME}.keys"