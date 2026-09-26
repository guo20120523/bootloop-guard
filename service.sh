#!/system/bin/sh
# Copyright (C) 2026  昱yu (QQ:3895958954)
# SPDX-License-Identifier: GPL-3.0-only
# This program comes with ABSOLUTELY NO WARRANTY; see LICENSE for details.
# ============================================================================
# Bootloop Guard - service.sh
#
# 本脚本在开机较晚阶段（late_start service）启动。
# 等待 sys.boot_completed=1（系统启动完成）后：
#   1. 把连续失败计数清零；
#   2. 把本次正常开机时“处于启用状态的模块列表”存入 good_modules.list，
#      供下次救砖时精准识别“上次正常开机后新增/启用”的嫌疑模块。
# 只要系统能正常进入桌面，计数器就会归零，不影响日常使用。
# ============================================================================

MODDIR=${0%/*}
COUNT_FILE="$MODDIR/boot_count"
LOG_FILE="$MODDIR/guard.log"
GOOD_LIST="$MODDIR/good_modules.list"

# 等待系统启动完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done

# 再观察 10 秒，防止“刚显示开机完成就立刻崩溃”的假成功
sleep 10

echo 0 > "$COUNT_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) [OK] 开机成功，失败计数已清零" >> "$LOG_FILE"

# ---- 保存正常开机的模块清单（原子写入：先写临时文件再改名）----
if [ -d /data/adb/modules ]; then
    TMP_LIST="$MODDIR/.good_modules.tmp"
    rm -f "$TMP_LIST"
    for d in /data/adb/modules/*; do
        [ -d "$d" ] || continue
        [ -f "$d/disable" ] && continue   # 已禁用的不算“正常启用”
        [ -f "$d/remove" ] && continue    # 待卸载的不算
        echo "${d##*/}" >> "$TMP_LIST"
    done
    if [ -f "$TMP_LIST" ]; then
        mv -f "$TMP_LIST" "$GOOD_LIST" 2>/dev/null && sync
        N=$(wc -l < "$GOOD_LIST" 2>/dev/null | tr -d ' \t')
        echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) [OK] 正常开机模块清单已更新（good_modules.list，共 $N 个）" >> "$LOG_FILE"
    fi
fi

exit 0
