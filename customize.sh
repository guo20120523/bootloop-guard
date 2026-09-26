#!/system/bin/sh
# Copyright (C) 2026  昱yu (QQ:3895958954)
# SPDX-License-Identifier: GPL-3.0-only
# This program comes with ABSOLUTELY NO WARRANTY; see LICENSE for details.
# ============================================================================
# Bootloop Guard - 安装脚本（由 Magisk 安装器自动执行）
# ============================================================================

# 0 = 让安装器自动解压模块内所有文件
SKIPUNZIP=0

ui_print "********************************"
ui_print "  Bootloop Guard v2.0.0 NEXT"
ui_print "  开机失败 → 冻结模块+解冻APP → 进 REC"
ui_print "********************************"
ui_print "- 连续 3 次开机失败后触发救砖"
ui_print "- 卡开机动画超 2 分钟触发救砖"
ui_print "- 触发时自动冻结嫌疑模块"
ui_print "- 同时解冻APP后台限制（备份式）"
ui_print "- 阈值/冻结/解冻配置: 模块目录 config.conf"
ui_print "- 冻结白名单   : 模块目录 whitelist.conf"
ui_print "- 运行日志     : 模块目录 guard.log"

# 设置权限：目录 755，普通文件 644，脚本文件 755
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/action.sh"       0 0 0755

ui_print "- 安装完成，重启后生效"
