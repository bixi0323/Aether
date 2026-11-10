# 脱离 SSH/API 会话的一次性 Aether 更新

当 Aether 本身承载 Codex/API 流量时，直接在当前 SSH 或 API 会话里重建
`aether-app` 可能导致会话中断。更新必须交给独立的 systemd 任务执行，不能依赖
当前 shell 一直在线。

## 相关文件

- `/opt/aether/deploy-aether-detached.sh`：通用部署脚本。
- `/opt/aether/docker-compose.custom.yml`：只覆盖应用镜像，并使用镜像内前端。
- `/root/aether-backups/`：数据库备份、部署日志和最终状态文件。
- `/opt/aether/deploy-pr818.sh`：2026-11-05 PR-818 更新的一次性历史脚本。

## 一次性更新命令

把下面整段一次性粘贴到服务器 shell。不要逐行手工执行部署步骤。

```bash
cd /opt/aether

UNIT="aether-update-$(date -u +%Y%m%dT%H%M%SZ)"
NEW_IMAGE='ghcr.io/bixi0323/aether:pr-818-5de69709132ca5391d285bceb54e99ed83b958ae'

printf '%s\n' "$UNIT" > /root/aether-backups/last-aether-update-unit

systemd-run \
  --unit="$UNIT" \
  --on-active=10s \
  --property=Type=oneshot \
  --property=TimeoutStartSec=30min \
  --property=KillMode=control-group \
  --setenv=NEW_IMAGE="$NEW_IMAGE" \
  --setenv=UPDATE_ID="${UNIT#aether-update-}" \
  /opt/aether/deploy-aether-detached.sh
```

`systemd-run` 返回后，部署任务已经脱离当前 SSH/API 会话。Aether 重启造成的连接
中断不会停止该任务。

如果成品镜像已经存在本机、明确不希望联网拉取，在 `systemd-run` 参数中增加：

```text
--setenv=PULL_IMAGE=0 \
```

该模式会使用 `--pull never`，镜像缺失时直接失败，不会在后台下载。

## 脚本执行顺序

1. 读取并标记当前应用镜像，用于自动回滚。
2. 创建 PostgreSQL custom-format 备份并执行 `pg_restore -l` 校验。
3. 拉取并确认新镜像；`PULL_IMAGE=0` 时只确认本地镜像且禁止联网拉取。
4. 在老应用仍在线时执行数据库迁移。
5. 只重建 `app`，不重建 PostgreSQL 和 Redis。
6. 等待容器健康检查和 HTTP 健康检查。
7. 新应用不健康时自动切回旧应用镜像。

## 断线后查看状态

重新连接后执行：

```bash
UNIT="$(cat /root/aether-backups/last-aether-update-unit)"

cat /root/aether-backups/aether-detached-deploy.status
journalctl -u "$UNIT.service" -b --no-pager -f

docker inspect aether-app \
  --format 'image={{.Config.Image}} health={{.State.Health.Status}}'
curl -fsS http://127.0.0.1:8084/health
```

最终状态文件只有以下两种结果：

```text
SUCCESS new_image=... old_image=... backup=... finished=...
FAILED  new_image=... old_image=... backup=... finished=...
```

systemd transient unit 在任务成功完成后可能自动消失，这是正常现象；以状态文件和
journal 日志为准。

## 回滚规则

脚本只自动回滚应用镜像，不自动回滚数据库。新镜像执行过的数据库迁移不会因为切回
旧镜像而撤销，因此失败时先保留现场并查看：

```bash
UNIT="$(cat /root/aether-backups/last-aether-update-unit)"
journalctl -u "$UNIT.service" -b --no-pager
docker logs --tail 200 aether-app
df -h /
```

备份路径记录在状态文件和部署日志中。当前 PR-818 备份为：

```text
/root/aether-backups/aether-pre-pr818-20261105T070825Z.dump
```

## 复用已有备份

只有确认已有备份完整且数据足够新时，才可跳过新备份。在 `systemd-run` 参数中增加：

```text
--setenv=USE_EXISTING_BACKUP=1 \
--setenv=EXISTING_BACKUP=/root/aether-backups/具体备份.dump \
```

## 注意事项

- `docker exec` 不支持 `-T`；`-T` 只用于 `docker compose run`。
- 不要在 SSH shell 中依赖 `set -e` 驱动整套远程更新，shell 退出会终止剩余步骤。
- 不要使用 `docker system prune -a` 或 `docker volume prune` 清理更新现场。
- 新镜像标签必须通过 `NEW_IMAGE` 传给脚本，不要直接修改正在运行容器的配置。
