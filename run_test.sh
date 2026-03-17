#!/bin/bash
swift build
./.build/debug/SmartWindow &
APP_PID=$!
sleep 5
kill $APP_PID
