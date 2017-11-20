#!/bin/bash
#Returns CPU name

cat /proc/cpuinfo | grep "model name" | cut -d ":" -f2 | head -n 1
