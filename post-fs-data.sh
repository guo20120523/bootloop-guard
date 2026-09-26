#!/system/bin/sh
# Copyright (C) 2026  昱yu (QQ:3895958954)
# SPDX-License-Identifier: GPL-3.0-only
# This program comes with ABSOLUTELY NO WARRANTY; see LICENSE for details.
# ============================================================================
# Bootloop Guard - post-fs-data.sh
#
# 本脚本在每次开机的极早期（post-fs-data 阶段）执行，此时系统远未启动完成。
#
# 功能一（失败计数）：每次开机都把失败计数 +1；若系统正常启动完成
#   （sys.boot_completed=1），service.sh 会把计数清零。连续失败达到
#   MAX_FAILS 次 → 冻结嫌疑模块后自动重启进入 Recovery。
#
# 功能二（卡屏看门狗）：启动一个后台看门狗。若 WATCHDOG_TIMEOUT 秒（默认 120s，
#   即 2 分钟）后系统仍未启动完成、且开机动画（bootanim，即“第二屏”）仍在
#   播放/重启 → 判定为卡开机动画，冻结嫌疑模块后自动重启进入 Recovery。
#
# 功能三（模块冻结，触发救砖时执行）：先在 /data/adb/modules 中把“嫌疑模块”
#   置为禁用（touch disable，Magisk 下次开机不再挂载它），再重启进 REC。
#   精准模式（默认）：只冻结“上次正常开机后新增/启用”的模块（与
#   good_modules.list 对比得出）；识别不出嫌疑人时回退为冻结除自身与
#   白名单外的全部模块。冻结机制参考自 magisk-brick-guardian（Kirk Lin）。
#
# 功能四（APP 解冻，触发救砖时执行）：把各用户的 package-restrictions.xml
#   改名备份（.bak-bootloopguard），系统下次启动自动重建。该文件记录系统的
#   应用后台限制/冻结名单，损坏或误冻结关键应用时会导致系统服务反复崩溃
#   无法开机。机制参考自 magisk-brick-guardian 的“APP 解冻”。
# ============================================================================

MODDIR=${0%/*}
COUNT_FILE="$MODDIR/boot_count"
LOG_FILE="$MODDIR/guard.log"
CONFIG_FILE="$MODDIR/config.conf"
GOOD_LIST="$MODDIR/good_modules.list"
FROZEN_LOG="$MODDIR/frozen_modules.log"
WHITELIST_FILE="$MODDIR/whitelist.conf"

# ---- 默认配置（可被 config.conf 覆盖）----
MAX_FAILS=3
WATCHDOG_ENABLE=true
WATCHDOG_TIMEOUT=120
FREEZE_MODULES=true
FREEZE_MODE=auto
UNFREEZE_APPS=true
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# 配置合法性检查
case "$MAX_FAILS" in ''|*[!0-9]*) MAX_FAILS=3 ;; esac
[ "$MAX_FAILS" -lt 1 ] && MAX_FAILS=3
case "$WATCHDOG_TIMEOUT" in ''|*[!0-9]*) WATCHDOG_TIMEOUT=120 ;; esac
[ "$WATCHDOG_TIMEOUT" -lt 60 ] && WATCHDOG_TIMEOUT=60
[ "$FREEZE_MODE" != "all" ] && FREEZE_MODE=auto

log_line() {
    echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) $1" >> "$LOG_FILE"
}

reboot_recovery() {
    # 依次尝试多种方式触发 reboot recovery（不同机型/系统版本兼容性兜底）
    /system/bin/reboot recovery 2>/dev/null && return 0
    /system/bin/setprop sys.powerctl "reboot,recovery" 2>/dev/null && return 0
    setprop sys.powerctl "reboot,recovery" 2>/dev/null && return 0
    resetprop sys.powerctl "reboot,recovery" 2>/dev/null
    return 0
}

# ============================================================================
# 冻结模块：在模块目录创建 disable 标志（Magisk 原生禁用机制）
#   - 永不冻结本模块自身
#   - whitelist.conf 中列出的模块不冻结（每行一个模块 id，# 为注释）
#   - FREEZE_MODE=auto：只冻结“上次正常开机后新增/启用”的嫌疑模块；
#     识别不出嫌疑人（无 good_modules.list 或无差异）→ 回退全量冻结
#   - FREEZE_MODE=all：直接冻结除自身与白名单外的全部模块
#   - 冻结名单记录到 frozen_modules.log，便于救回后核对/恢复
# ============================================================================
freeze_modules() {
    case "$FREEZE_MODULES" in
        1|true|yes|on) : ;;
        *) log_line "[*] 模块冻结功能已关闭（FREEZE_MODULES=$FREEZE_MODULES）"; return 0 ;;
    esac
    if [ ! -d /data/adb/modules ]; then
        log_line "[x] /data/adb/modules 不存在，跳过模块冻结"
        return 1
    fi

    MODID=${MODDIR##*/}
    : > "$FROZEN_LOG"

    # 白名单规范化：去 CR、去首尾空白、去注释与空行（Windows 编辑的文件也能用）
    WL_TMP="$MODDIR/.whitelist.norm"
    rm -f "$WL_TMP"
    if [ -f "$WHITELIST_FILE" ]; then
        tr -d '\r' < "$WHITELIST_FILE" 2>/dev/null | \
            sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                -e '/^#/d' -e '/^$/d' > "$WL_TMP" 2>/dev/null
    fi

    in_whitelist() {
        [ -f "$WL_TMP" ] || return 1
        grep -qx "$1" "$WL_TMP" 2>/dev/null
    }

    # ---- 收集嫌疑人：启用中、但不在“上次正常开机清单”里的模块 ----
    SUSPECTS=""
    if [ "$FREEZE_MODE" = "auto" ] && [ -s "$GOOD_LIST" ]; then
        for d in /data/adb/modules/*; do
            [ -d "$d" ] || continue
            m=${d##*/}
            [ "$m" = "$MODID" ] && continue
            [ -f "$d/disable" ] && continue   # 已禁用的跳过
            [ -f "$d/remove" ] && continue    # 待卸载的跳过
            grep -qx "$m" "$GOOD_LIST" 2>/dev/null && continue
            SUSPECTS="$SUSPECTS $m"
        done
    fi

    if [ -n "$SUSPECTS" ]; then
        log_line "[!] 精准冻结：上次正常开机后新增/启用的模块"
        TARGETS="$SUSPECTS"
    else
        if [ "$FREEZE_MODE" = "all" ]; then
            log_line "[!] 全量冻结模式（FREEZE_MODE=all）"
        else
            log_line "[!] 未识别出嫌疑模块（无历史清单或无新增模块），回退为全量冻结"
        fi
        TARGETS=""
        for d in /data/adb/modules/*; do
            [ -d "$d" ] || continue
            m=${d##*/}
            [ "$m" = "$MODID" ] && continue
            [ -f "$d/disable" ] && continue
            [ -f "$d/remove" ] && continue
            TARGETS="$TARGETS $m"
        done
    fi

    N=0
    for m in $TARGETS; do
        if in_whitelist "$m"; then
            log_line "[*] 白名单豁免: $m"
            continue
        fi
        if touch "/data/adb/modules/$m/disable" 2>/dev/null; then
            echo "$m" >> "$FROZEN_LOG"
            N=$((N + 1))
            log_line "[!] 已冻结模块: $m"
        else
            log_line "[x] 冻结失败（无权限或目录异常）: $m"
        fi
    done
    rm -f "$WL_TMP"

    if [ "$N" -eq 0 ]; then
        log_line "[*] 没有需要冻结的模块"
    else
        log_line "[!] 冻结完成，共 $N 个模块（名单见模块目录 frozen_modules.log）"
    fi
    sync
    return 0
}

# ============================================================================
# APP 解冻：把各用户的 package-restrictions.xml 改名备份
#   该文件记录系统的应用后台限制/滥用冻结名单；它损坏或关键应用被误冻结时
#   会导致 system_server 反复崩溃无法开机。改名后系统启动时自动重建，
#   所有被后台冻结的应用随之解冻。原文件保留为 .bak-bootloopguard 可恢复。
# ============================================================================
unfreeze_apps() {
    case "$UNFREEZE_APPS" in
        1|true|yes|on) : ;;
        *) log_line "[*] APP解冻功能已关闭（UNFREEZE_APPS=$UNFREEZE_APPS）"; return 0 ;;
    esac

    FOUND=0
    for f in /data/system/users/*/package-restrictions.xml; do
        [ -f "$f" ] || continue
        FOUND=$((FOUND + 1))
        if mv -f "$f" "$f.bak-bootloopguard" 2>/dev/null; then
            log_line "[!] 已解冻APP后台限制: $f（原文件备份为 .bak-bootloopguard，开机自动重建）"
        else
            log_line "[x] APP解冻失败（无权限或分区未就绪）: $f"
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        log_line "[*] 未找到 package-restrictions.xml（可能无需解冻）"
    fi
    sync
    return 0
}

# ---- 功能一：读取并累加失败计数（非法值按 0 处理）----
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE" 2>/dev/null)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

log_line "[*] 连续第 $COUNT 次开机尝试（阈值 $MAX_FAILS，看门狗 $WATCHDOG_ENABLE/${WATCHDOG_TIMEOUT}s，冻结 $FREEZE_MODULES/$FREEZE_MODE，APP解冻 $UNFREEZE_APPS）"

# ---- 日志瘦身：超过 200 行只保留最后 100 行 ----
if [ -f "$LOG_FILE" ]; then
    LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' \t')
    case "$LINES" in ''|*[!0-9]*) LINES=0 ;; esac
    if [ "$LINES" -gt 200 ]; then
        tail -n 100 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

# ---- 连续失败达到阈值：冻结模块 → 清零计数 → 重启进 Recovery ----
if [ "$COUNT" -ge "$MAX_FAILS" ]; then
    log_line "[!] 已连续 $COUNT 次未能完成开机，执行模块冻结 + APP解冻并重启进入 Recovery 模式"
    freeze_modules
    unfreeze_apps
    echo 0 > "$COUNT_FILE"   # 后清零，避免从 Recovery 正常开机后又立刻触发
    sync
    sleep 3
    reboot_recovery
    # 若重启未生效，等待后脚本退出，本次开机照常继续（不会变砖）
    sleep 15
    exit 0
fi

# ---- 功能二：卡开机动画看门狗（后台运行，开机成功后自动退出）----
case "$WATCHDOG_ENABLE" in
    1|true|yes|on)
        (
            sleep "$WATCHDOG_TIMEOUT"
            EXTRA=0
            while [ "$EXTRA" -lt 60 ]; do
                # 系统已启动完成 → 看门狗任务结束
                [ "$(/system/bin/getprop sys.boot_completed)" = "1" ] && exit 0
                ANIM=$(/system/bin/getprop init.svc.bootanim)
                case "$ANIM" in
                    running|restarting|Restarting)
                        # 超时后开机动画仍在播放/反复重启 → 判定“卡第二屏”
                        echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) [!] 开机动画已持续超过 ${WATCHDOG_TIMEOUT}s，判定卡死，执行模块冻结 + APP解冻并重启进入 Recovery" >> "$LOG_FILE"
                        freeze_modules
                        unfreeze_apps
                        echo 0 > "$COUNT_FILE"   # 清零，避免从 REC 回来后立刻再次触发
                        sync
                        reboot_recovery
                        exit 0
                        ;;
                    *)
                        # 动画已停止但 boot_completed 未置位：
                        # 多半是在锁屏界面等待输入密码（FBE 加密机型），
                        # 属正常情况，每分钟复查一次，最多再观察 60 分钟
                        sleep 60
                        EXTRA=$((EXTRA + 1))
                        ;;
                esac
            done
        ) </dev/null >/dev/null 2>&1 &
        ;;
esac

exit 0
