# mini-cicd

轻量打包发布平台：在一台机器上跑 **Woodpecker**（Web UI、流水线历史），对接 GitHub / Gitea / Forgejo。各业务仓库自己写 `.woodpecker.yaml` 做编译和发布，本仓库不绑定任何业务项目。

比 Jenkins / GitLab / Gitea+runner 更轻：只有 CI，没有自带 Git 托管。

Agent 使用 **local backend**：步骤在 CI 宿主机执行，直接用本机已装的 `go` / `node` / `rsync` 等。只适合 **可信私有仓库**。

## 安装（CI 机）

需要：Docker Compose、能访问 Git、按要编的语言装好工具，以及 `git`、`rsync`、`ssh`、`curl`、`bash`。

```bash
cd /path/to/mini-cicd
sudo bash install-woodpecker-agent.sh
cp .env.example .env
# 填写 WOODPECKER_HOST、WOODPECKER_AGENT_SECRET、Git OAuth
# WOODPECKER_AGENT_SECRET：openssl rand -hex 32
docker compose --env-file .env up -d --build
```

浏览器打开 `WOODPECKER_HOST`（默认 `:8000`）。在 Git 平台创建 OAuth 应用，回调一般为 `{WOODPECKER_HOST}/authorize`。登录后添加要发布的仓库，确认 webhook 已指向 Woodpecker。

`.env` 不要提交。Gitee 无官方 forge 时，用 GitHub / Gitea / Forgejo。

可选：把 `deploy-remote.sh` 放到宿主机 `/opt/woodpecker/deploy-remote.sh`，各仓库流水线共用，不必每份仓库复制一份。

## 业务仓库怎么接

1. 把 [examples/woodpecker.yaml](examples/woodpecker.yaml) 复制到该仓库根目录，改名为 `.woodpecker.yaml`。
2. 把 `build` 步骤改成这个仓库自己的打包命令。
3. 在 Woodpecker 该仓库 Secrets 里配置：`deploy_host`、`deploy_user`、`ssh_private_key`。发布路径、`REMOTE_AFTER`、健康检查 URL 写在 `.woodpecker.yaml` 里。
4. 目标机放 CI 公钥；若要用 sudo，在 visudo 里只放开那一条命令。

通用同步脚本：[deploy-remote.sh](deploy-remote.sh)。不要把生产配置或口令写进仓库或流水线日志。

## 安全

`WOODPECKER_BACKEND=local` 没有容器隔离。compose 里的 agent 容器只做 `nsenter`，宿主机上的 `woodpecker-agent` 往往以 root 运行。不要让不可信 fork 跑流水线。
