#!/bin/bash
# SIMPLE MODE (No local file check)

USERNAME=$1

# 1. Safety Check (Basic Alphanumeric)
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then exit 1; fi

# 2. Fetch directly from GitHub
curl -s --connect-timeout 5 "https://github.com/${USERNAME}.keys"