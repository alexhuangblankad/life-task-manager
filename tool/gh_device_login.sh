#!/bin/bash
# 等 GitHub 设备授权完成，然后把 token 直接喂给 gh（token 不会打印出来）
set -u
export PATH="$PATH:/c/Program Files/GitHub CLI"

FILE="E:/hermes/日程软件开发/.gh_device.txt"
DEVICE_CODE=$(grep '^DEVICE_CODE=' "$FILE" | cut -d= -f2-)
INTERVAL=$(grep '^INTERVAL=' "$FILE" | cut -d= -f2-)
INTERVAL=${INTERVAL:-5}
# GitHub 对轮询很敏感，起步就慢一点，别被 slow_down 掐掉
if [ "$INTERVAL" -lt 10 ]; then INTERVAL=10; fi

echo "开始等待授权（每 ${INTERVAL}s 查一次，最多 15 分钟）…"
for i in $(seq 1 90); do
  sleep "$INTERVAL"
  POLL=$(curl -s -X POST -H "Accept: application/json" \
    -d "client_id=178c6fc778ccc68e1d6a&device_code=${DEVICE_CODE}&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
    https://github.com/login/oauth/access_token)
  case "$POLL" in
    *access_token*)
      echo "授权成功，正在写入 gh 凭据…"
      echo "$POLL" | sed 's/.*"access_token":"\([^"]*\)".*/\1/' | timeout 30 gh auth login --with-token \
        || { echo "WITH_TOKEN_FAILED"; exit 1; }
      gh auth setup-git
      gh auth status
      echo "LOGIN_COMPLETE"
      exit 0 ;;
    *authorization_pending*) ;;
    *slow_down*) INTERVAL=$((INTERVAL + 10)); echo "（服务器要求慢一点：${INTERVAL}s）" ;;
    *expired_token*) echo "CODE_EXPIRED — 要重新发起授权"; exit 2 ;;
    *access_denied*) echo "USER_DENIED"; exit 3 ;;
    "") echo "（这次没拿到响应，继续等）" ;;
    *) echo "UNEXPECTED: $POLL" ;;
  esac
done
echo "TIMEOUT — 15 分钟内没等到授权"
exit 5
