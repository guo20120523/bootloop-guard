# Bootloop Guard（开机失败 → 冻结模块 + 解冻APP → 自动进 REC）

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**专为无音量加减键设备设计的全新一代自动救砖 Magisk 模块**：传统救砖依赖音量键组合（手动进 REC、Magisk 安全模式），而无音量键设备（部分平板/车机/电视盒子/学习机）一旦变砖就彻底抓瞎。本模块把整套救砖流程做成**全自动、零按键**：当设备**无法正常开机**时，先**自动冻结致砖嫌疑模块**（下次开机 Magisk 不再挂载它们）、**解冻被系统后台冻结的应用**，再重启进入 **Recovery 模式**，方便进 REC 清数据、刷机或救砖。支持两种独立的触发条件：

| # | 触发条件 | 默认参数 |
|---|---|---|
| ① | **连续多次开机失败**（反复重启于开机动画） | 连续 **3** 次 |
| ② | **卡在开机动画（第二屏）超时** | 超过 **2 分钟** |

任一条件触发后的动作：**冻结嫌疑模块 → 解冻 APP 后台限制 → 清零计数 → 重启进 Recovery**。

## 工作原理

### 条件①：连续失败计数

1. **`post-fs-data.sh`**（每次开机的极早期执行，此时系统远未启动完成）：把失败计数 `boot_count` **+1**；若计数 **≥ MAX_FAILS**，说明之前几次开机全部失败 → 冻结模块、清零计数，然后 `reboot recovery`。
2. **`service.sh`**（开机较后阶段执行）：等到 `sys.boot_completed=1`（系统完整启动成功）后把计数**清零**，并保存本次正常开机的模块清单。

只要有一次成功进入桌面，计数立即归零；只有连续失败达到阈值才会触发。

### 条件②：卡开机动画看门狗

`post-fs-data.sh` 会启动一个**后台看门狗进程**（独立于系统服务，系统服务卡死它也能工作）：

1. 等待 `WATCHDOG_TIMEOUT` 秒（默认 120，即 2 分钟）；
2. 到时间后检查：`sys.boot_completed` 仍未置 1 **且** `init.svc.bootanim` 仍为 `running/restarting`（开机动画还在转）→ 判定"卡第二屏" → 冻结模块、清零计数并 `reboot recovery`；
3. 若系统已正常启动完成，看门狗自动退出，无任何残留。

**为什么还要看 bootanim 状态？** 两个好处：

- **避免误判锁屏等密码**：FBE 加密机型设了锁屏密码时，系统其实已启动完成，但要输完密码 `boot_completed` 才置 1。此时开机动画早已退出（`bootanim=stopped`），看门狗会识别为"在等密码"继续观察，不会误触发。
- **识别动画崩溃循环**：zygote/system_server 崩溃导致的动画反复重启（`bootanim=restarting`）也能被识别，这种故障整机不重启、条件①的计数器覆盖不到。

### 模块冻结（v1.2.0 新增，合入自 magisk-brick-guardian 的机制）

触发救砖时，先把嫌疑模块**冻结**（在对应模块目录创建 `disable` 标志文件，这是 Magisk 的原生禁用机制，下次开机不再挂载该模块），再进 REC。这样即使你不进 REC 操作、直接从 REC 重启回系统，致砖模块也已经被隔离，大概率能正常开机。

**精准模式（`FREEZE_MODE=auto`，默认）**：

1. 每次**正常开机成功**后，`service.sh` 把当前处于启用状态的模块名单保存到 `good_modules.list`；
2. 救砖时逐个对比 `/data/adb/modules/` 下的模块：**不在清单里的 = 上次正常开机后新增/新启用的嫌疑模块**，只冻结它们；
3. 识别不出嫌疑人（清单不存在、或没有任何新增模块——比如是系统更新导致的变砖）→ **回退为全量冻结**（除自身与白名单外的所有模块）。

**全量模式（`FREEZE_MODE=all`）**：跳过对比，直接冻结全部模块（除自身与白名单）。

**豁免规则（任何模式都生效）**：

- 本模块自身（`bootloop_guard`）永远不被冻结；
- `whitelist.conf` 白名单内的模块不被冻结；
- 已禁用（有 `disable` 标志）或待卸载（有 `remove` 标志）的模块自动跳过。

**冻结记录**：每次救砖冻结的模块名单写入 `frozen_modules.log`，点 Magisk 里本模块的"操作"按钮可查看哪些还在冻结状态。

**解冻方法**（救回系统后）：删除对应模块目录下的 `disable` 文件再重启即可，例如：

```sh
su
rm /data/adb/modules/<模块id>/disable
reboot
```

### APP 解冻（v2.0.0 新增，合入自 magisk-brick-guardian 的机制）

系统把"应用后台限制/滥用冻结名单"记录在 `/data/system/users/<用户id>/package-restrictions.xml` 中。这个文件**损坏**、或某个**关键应用被误冻结**时，会导致 system_server 反复崩溃、系统永远进不了桌面——救砖时只冻结 Magisk 模块是解决不了的。

触发救砖时，本模块把各用户的该文件**改名备份**为 `package-restrictions.xml.bak-bootloopguard`（不直接删除，可恢复）。系统下次启动时找不到原文件会**自动重建**，所有被后台冻结的应用随之解冻。

**恢复原名单**（一般不需要）：在 REC 或有 root 的环境里把备份改回原名即可：

```sh
mv /data/system/users/0/package-restrictions.xml.bak-bootloopguard \
   /data/system/users/0/package-restrictions.xml
```

> 副作用：重建后各应用的后台限制状态（如省电策略白名单外的限制记录）会回到系统默认，需要系统重新学习，对日常使用无实质影响。

```
开机 → 计数+1 ──成功进桌面──→ 计数清零 + 保存正常模块清单（service.sh）
  │        └─ 看门狗启动 ──2分钟后── 动画还在转 → 冻结模块+解冻APP → 进 REC
  │                             └─ 已进桌面/在等密码 → 自动退出/继续观察
  └─ 失败(重启) → 再+1 → 再失败 → 第3次 → 冻结模块+解冻APP → 进 REC
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块信息 |
| `post-fs-data.sh` | 核心逻辑：失败计数 + 卡动画看门狗 + 模块冻结 + APP 解冻 |
| `service.sh` | 开机成功后清零计数、保存正常模块清单 |
| `action.sh` | Magisk 管理器"操作"按钮：查看状态/冻结记录并手动清零 |
| `config.conf` | 配置触发阈值、看门狗参数、冻结开关与模式 |
| `whitelist.conf` | 冻结白名单（每行一个模块 id） |
| `customize.sh` | 安装时设置文件权限 |
| `boot_count` / `guard.log` | 运行时自动生成：当前计数 / 运行日志 |
| `good_modules.list` | 运行时自动生成：上次正常开机的启用模块清单 |
| `frozen_modules.log` | 运行时自动生成：上次救砖冻结的模块名单 |

## 安装方法（推荐用 Magisk App）

1. 把 `bootloop_guard_v2.0.0-NEXT.zip` 拷到手机；
2. 打开 **Magisk** → **模块** → **从本地安装** → 选择该 zip；
3. 安装完成后**重启手机**即生效。

> 模块数据保存在 `/data/adb/modules/bootloop_guard/`。

> ⚠️ **不要与其他防砖/救砖模块同时安装**（如 magisk-brick-guardian、自动神仙救砖等）：多个模块各自计数、各自冻结、各自重启，会互相干扰导致行为不可预期。本模块 v1.2.0 已合入 brick-guardian 的核心冻结机制，二选一即可。

## 配置说明

用 root 文件管理器（或 `adb shell`）编辑：

```
/data/adb/modules/bootloop_guard/config.conf
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `MAX_FAILS` | `3` | 连续失败多少次后触发救砖 |
| `WATCHDOG_ENABLE` | `true` | 卡动画看门狗开关（`false` 关闭） |
| `WATCHDOG_TIMEOUT` | `120` | 看门狗超时秒数（2 分钟；最低 60） |
| `FREEZE_MODULES` | `true` | 触发时是否先冻结模块（`false` 则只进 REC） |
| `FREEZE_MODE` | `auto` | `auto`=精准冻结嫌疑模块（识别不出则全量）；`all`=直接全量冻结 |
| `UNFREEZE_APPS` | `true` | 触发时是否同时解冻 APP 后台限制（package-restrictions.xml 改名备份） |

冻结白名单（永远不会被冻结的模块）：

```
/data/adb/modules/bootloop_guard/whitelist.conf
```

每行一个模块 id（即 `/data/adb/modules/` 下的目录名），`#` 开头为注释。若你之前使用 magisk-brick-guardian，可直接把它的 `白名单.conf` 内容复制过来。

修改后无需重装模块，下次开机自动生效。

## 测试方法

### 验证条件①（失败计数 → 冻结 → 进 REC）

不用真把手机搞坏，手动模拟失败计数即可：

```sh
# adb shell（需 root）
su
echo 2 > /data/adb/modules/bootloop_guard/boot_count   # 阈值3时，写入2
reboot
```

下次开机会在 post-fs-data 阶段把计数变成 3，达到阈值 → **冻结嫌疑模块（日志可查）→ 手机在开机动画出现前自动重启进 Recovery**。在 REC 里选"重启系统"即可正常开机（触发前计数已被清零，不会循环进 REC）。

> 注意：测试时若不想真的冻结其他模块，先把 `config.conf` 里 `FREEZE_MODULES` 改为 `false`，测完再改回来；或在 `whitelist.conf` 里把重要模块都列上。

### 验证精准冻结逻辑

```sh
su
# 查看上次正常开机保存的模块清单
cat /data/adb/modules/bootloop_guard/good_modules.list
# 手动触发一次"嫌疑人识别"演练（只查看，不冻结）：装个新模块后不重启，
# 它不在 good_modules.list 里，下次救砖时就会被精准冻结
```

### 验证条件②（看门狗在运行）

正常开机后 2 分钟内（看门狗存活期间）：

```sh
su
ps -A | grep sleep    # 能看到看门狗的 sleep 120 进程
```

2 分钟后系统已启动完成，看门狗确认 `boot_completed=1` 后自动退出。卡屏触发的完整链路只能在真卡死时验证；日志会记录每次触发：

```sh
cat /data/adb/modules/bootloop_guard/guard.log
```

## 卸载与故障排除

- 正常卸载：Magisk App → 模块 → 移除 → 重启。
- 解冻被冻结的模块：删除 `/data/adb/modules/<模块id>/disable` 后重启（或参考 `frozen_modules.log` 逐个恢复）。
- 若模块导致问题无法开机（理论上不会，但以防万一）：
  - **有音量键设备**：开机出现开机动画时按住**音量减**进入 Magisk 安全模式，所有模块将被禁用；重启后到 Magisk 里移除本模块。
  - **无音量键设备**（本模块的主要使用场景）：本模块自身就是救砖通道——连续强制重启 3 次让它自然触发进 REC，在 REC 里删除目录 `/data/adb/modules/bootloop_guard`；或用 `adb wait-for-device shell` 在系统启动早期抢删模块目录。

## 注意事项

1. **条件①统计的是"开机尝试次数"**：设备彻底卡死不动时不计数（由条件②兜底）；卡死时你每次长按电源强制重启都会计数，连续 3 次后同样触发。
2. **连续 3 次手动断电/强制关机**（在系统启动完成前）也会触发条件①，属预期行为——此时若触发了全量冻结，救回后参考 `frozen_modules.log` 解冻即可。
3. **2 分钟的看门狗比较激进**：大版本 OTA / 刷大包后的首次开机要做应用优化，开机动画很容易超过 2 分钟而触发。此时从 REC 重启即可（已优化的应用不会重做，第二次开机通常能在时限内完成）；如果嫌麻烦，刷机/OTA 前可把 `WATCHDOG_TIMEOUT` 临时调大到 900~1800，或把 `WATCHDOG_ENABLE` 改为 `false`。
4. **设备硬死机**（内核挂死、画面完全定格）时看门狗进程同样被冻结，无法触发——这种情况只能靠人工强制重启，由条件①计数兜底。
5. 触发进 REC 前会**先冻结模块、解冻 APP、再清零计数**，避免从 REC 重启回系统后立刻又触发造成死循环。
6. **APP 解冻的影响**：`package-restrictions.xml` 重建后，各应用的后台限制/冻结状态回到系统默认（原文件已备份为 `.bak-bootloopguard`，可手动恢复）；这是救砖的必要代价，正常使用无感知。
7. **精准冻结依赖 good_modules.list**：该清单在每次正常开机成功后更新。新装/新启用的模块**第一次重启就失败**时会被精准识别；若模块装好但还没成功开过一次机就出了其他问题，它也会被当作嫌疑人——这正是期望行为。
8. 需要 **Magisk v20.4+**；"操作"按钮（action.sh）需要 Magisk v24+，旧版本忽略该文件不影响使用。
9. 本 zip 为 Magisk App 直装格式；如需在 Recovery 里线刷，请使用 Magisk 官方模块模板加入 `META-INF` 安装器重新打包。

## 开源协议

本项目以 **GNU General Public License v3.0**（GPL v3）开源，完整协议文本见 [LICENSE](LICENSE)。

Copyright (C) 2026 昱yu（QQ:3895958954）

- 可自由使用、修改、再分发；衍生作品必须以相同协议（GPL v3）开源并保留版权声明。
- 本程序**不提供任何担保**（ABSOLUTELY NO WARRANTY），因使用本模块导致的任何后果需自行承担。

## 致谢

- 模块冻结机制（精准识别嫌疑模块 + `disable` 标志冻结 + 白名单）与 APP 解冻机制（处理 `package-restrictions.xml`）参考自 [magisk-brick-guardian](https://github.com/kirklin/magisk-brick-guardian)（作者 Kirk Lin），已精简适配本模块的触发流程（解冻改为改名备份而非直接删除，可恢复）。

## 版本历史

- **v2.0.0-NEXT**：合入 **APP 解冻**功能——触发救砖时把 `/data/system/users/*/package-restrictions.xml` 改名备份（`.bak-bootloopguard`），系统重启自动重建，解除应用后台冻结/限制；新增 `UNFREEZE_APPS` 开关（默认开）；action.sh 显示解冻开关与备份存在状态。
- **v1.2.0**：合入**模块冻结**功能——触发救砖时先冻结嫌疑模块再进 REC；精准模式自动识别"上次正常开机后新增/启用"的模块（识别不出回退全量冻结）；新增 `whitelist.conf` 白名单、`good_modules.list` 正常清单、`frozen_modules.log` 冻结记录；action.sh 显示冻结状态。
- **v1.1.1**：看门狗默认超时从 10 分钟调整为 **2 分钟**；更新作者信息（昱yu，QQ:3895958954）。
- **v1.1.0**：新增条件②——卡开机动画（第二屏）超时自动进 REC（可配置开关/时长，智能区分锁屏等密码场景）。
- **v1.0.0**：首版，条件①——连续 3 次开机失败自动进 REC。
