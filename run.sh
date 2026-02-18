#!/bin/bash
cd "$(dirname "$0")"
source .env 2>/dev/null
export GROQ_API_KEY
swift run
