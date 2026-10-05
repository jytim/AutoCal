#!/bin/bash
# 若搜尋服務沒在跑就啟動。開機與每 5 分鐘呼叫，可重複執行。
cd $HOME/services/gateway
pgrep -f "python3 $HOME/services/gateway/[s]earch.py" >/dev/null && exit 0
nohup python3 $HOME/services/gateway/search.py >> search.log 2>&1 &
echo "$(date -Is) started search" >> ensure.log
