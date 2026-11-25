# orca-relay-build

从上游 [stablyai/orca](https://github.com/stablyai/orca) 按需稀疏拉取 `cloud/` 目录，编译并发布纯 JS 生产运行包（`orca-relay-bundle.tar.gz`），供 PVE LXC（Node.js 24 + systemd + SQLite）直接部署。

## 低负载机制说明

1. **零克隆秒级预检**：每次运行先通过轻量 API 检查上游最新正式 Release Tag 与 `cloud/` 目录树哈希（Tree SHA）；若 `cloud/` 目录未发生任何代码变动，2 秒内直接退出，不拉代码、不装依赖。
2. **稀疏浅克隆**：仅当 `cloud/` 确实更新时，才以 `--depth 1 --filter=blob:none` 稀疏检出 `cloud/` 子目录（约 1~2 MB），并仅安装 `@orca-cloud/relay` 所需的精简依赖。
3. **低频错峰触发**：每周仅定检 1 次，平时随时可在 Actions 页面点击 **Run workflow** 手动构建（支持指定 Tag）。
4. **本地补丁支持**：如需自定义修改 Relay 源码，将 `.patch` 文件放入 [`patches/`](./patches) 目录即可在构建时自动应用。

---

## PVE LXC 首次部署步骤（Debian 12 / Ubuntu 24.04）

### 1. 安装 Node.js 24 与基础工具

```bash
apt-get update && apt-get install -y curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs
node -v   # 确认 >= v24
```

### 2. 创建运行用户与数据/配置目录

```bash
useradd --system --home-dir /var/lib/orca-relay --create-home --shell /usr/sbin/nologin orca-relay
mkdir -p /etc/orca-relay /opt/orca-relay
```

将 [`deploy/relay.env.example`](./deploy/relay.env.example) 内容写入 `/etc/orca-relay/relay.env` 并修改你的域名和密钥：

```bash
# 生成 32 字节以上签名密钥
openssl rand -base64 32
chmod 600 /etc/orca-relay/relay.env
```

### 3. 拉取最新构建包并配置 systemd

```bash
mkdir -p /opt/orca-relay/bin
curl -fsSL https://raw.githubusercontent.com/tiaot33/orca-relay-build/main/deploy/install-or-update.sh -o /opt/orca-relay/bin/install-or-update.sh
chmod +x /opt/orca-relay/bin/install-or-update.sh

curl -fsSL https://raw.githubusercontent.com/tiaot33/orca-relay-build/main/deploy/orca-relay.service -o /etc/systemd/system/orca-relay.service

# 首次拉取最新 Release（国内网络可加 GITHUB_PROXY="https://ghfast.top/"）
/opt/orca-relay/bin/install-or-update.sh

systemctl daemon-reload
systemctl enable --now orca-relay
curl -s http://127.0.0.1:8080/health
```

### 4. 日常更新 / 回滚

```bash
# 一键检查更新（有新版自动校验 SHA256、软链切换、重启并做 /health 探活，失败自动回滚）
sudo GITHUB_PROXY="https://ghfast.top/" /opt/orca-relay/bin/install-or-update.sh
```

---

## Caddy 反代与客户端切换

- **Caddy 配置**：参考 [`deploy/Caddyfile.example`](./deploy/Caddyfile.example)。
- **桌面端切换**：启动 Orca 桌面端时注入环境变量 `ORCA_RELAY_URL=https://relay.yourdomain.com`（若有非 443 端口一并带上），然后用手机 App 重新扫码配对即可。
