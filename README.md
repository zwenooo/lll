# lll

一个一键引导脚本：安装 GitHub CLI(gh) → 登录 → 执行 XrayR 安装。

快速开始（最新版安装）

- 在线一键执行（Root 账户或具备 sudo 权限）
```
bash <(curl -fsSL https://raw.githubusercontent.com/zwenooo/lll/master/bootstrap.sh)
```

- 指定 XrayR 版本（示例 v1.2.3）
```
XRY_VERSION=v1.2.3 bash <(curl -fsSL https://raw.githubusercontent.com/zwenooo/lll/master/bootstrap.sh)
```

可选：使用 Personal Access Token 非交互登录 gh

- 事先导出环境变量（推荐最小权限：repo）
```
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
然后运行上面的安装命令即可，脚本会自动用 token 完成 gh 登录。

注意
- 脚本会尝试使用 apt/dnf/yum/zypper/apk 安装 gh，若不可用则从 GitHub Releases 下载二进制安装。
- gh 登录默认走交互模式；无浏览器环境会显示验证码与 URL，按提示在任意有浏览器的设备完成授权。
- 安装完成后，可用命令 `XrayR` 打开管理菜单（或执行 `XrayR status`/`XrayR log` 等）。
