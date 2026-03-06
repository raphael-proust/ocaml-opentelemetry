#!/bin/sh
git rev-parse --git-path index 2>/dev/null || echo /dev/null
