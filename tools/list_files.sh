#!/usr/bin/env bash
# @tool List files in a directory with details
# @param path:string The directory path (default: current directory)
ls -la "${1:-.}" 2>&1
