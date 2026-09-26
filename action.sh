#!/system/bin/sh
# Copyright (C) 2026  昱yu (QQ:3895958954)
# SPDX-License-Identifier: GPL-3.0-only
# This program comes with ABSOLUTELY NO WARRANTY; see LICENSE for details.
# ============================================================================
# Bootloop Guard - action.sh
# 在 Magisk 管理器的模块列表中点击“操作 / Action”按钮时执行
# 功能：显示当前状态（含冻结功能状态与上次冻结记录），并把连续失败计数清零
# ============================================================================

MODDIR=${0%/*}
COUNT_FILE="$MODDIR/boot_count"
CONFIG_FILE="$MODDIR/config.conf"
GOOD_LIST="$MODDIR/good_modules.list"
FROZEN_LOG="$MODDIR/frozen_modules.log"

MAX_FAILS=3
WATCHDOG_ENABLE=true
WATCHDOG_TIMEOUT=120
FREEZE_MODULES=true
FREEZE_MODE=auto
UNFREEZE_APPS=true
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
case "$MAX_FAILS" in ''|*[!0-9]*) MAX_FAILS=3 ;; esac
case "$WATCHDOG_TIMEOUT" in ''|*[!0-9]*) WATCHDOG_TIMEOUT=120 ;; esac

COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

GOOD_N=0
[ -f "$GOOD_LIST" ] && GOOD_N=$(wc -l < "$GOOD_LIST" 2>/dev/null | tr -d ' \t')
case "$GOOD_N" in ''|*[!0-9]*) GOOD_N=0 ;; esac

echo "========= Bootloop Guard ========="
echo "当前连续开机失败计数 : $COUNT"
echo "失败触发阈值         : $MAX_FAILS 次"
echo "卡动画看门狗         : $WATCHDOG_ENABLE（超时 ${WATCHDOG_TIMEOUT}s）"
echo "触发时冻结模块       : $FREEZE_MODULES（模式 $FREEZE_MODE）"
echo "触发时解冻APP        : $UNFREEZE_APPS（package-restrictions.xml 改名备份）"
if ls /data/system/users/*/package-restrictions.xml.bak-bootloopguard >/dev/null 2>&1; then
    echo "APP解冻备份          : 存在（.bak-bootloopguard，可改回原名恢复）"
fi
echo "正常开机模块清单     : $GOOD_N 个（good_modules.list）"
echo "计数文件             : $COUNT_FILE"
echo "日志文件             : $MODDIR/guard.log"
echo "=================================="

if [ -s "$FROZEN_LOG" ]; then
    echo "上次救砖冻结的模块："
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        if [ -f "/data/adb/modules/$m/disable" ]; then
            echo "  [已冻结] $m"
        else
            echo "  [已恢复] $m"
        fi
    done < "$FROZEN_LOG"
    echo "（恢复方法：删除对应模块目录下的 disable 文件后重启）"
    echo "=================================="
fi

echo 0 > "$COUNT_FILE"
echo "已将失败计数清零。"

exit 0
