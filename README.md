# cyfs_zsh

CYFS 的个人 Zsh 配置仓库。

包含 Oh My Zsh、Powerlevel10k、zplug、fzf 0.39.0、命令自动建议、语法高亮、增强补全、历史子串搜索，以及 git / systemd / rsync / sudo / extract / z / cp / safe-paste / colored-man-pages 插件。

## 安装

支持 Ubuntu / Debian 的 x86_64、ARM64，以及已安装 Homebrew 的 macOS。

```bash
git clone https://github.com/CYFS3/cyfs_zsh.git ~/work/cyfs_zsh
cd ~/work/cyfs_zsh
bash deploy.sh
exec zsh -l
```

也可以使用在线入口，自动克隆本仓库：

```bash
curl -fsSL https://raw.githubusercontent.com/CYFS3/cyfs_zsh/main/deploy.sh | bash
```

请以普通用户运行，安装系统依赖和切换默认 shell 时可能需要 sudo 密码。`bash deploy.sh --no-chsh` 只部署配置；`--repo /path/to/cyfs_zsh` 指定已有仓库。

安装后新建终端或重新连接 SSH 即可默认进入 Zsh；已有终端运行 `exec zsh -l`。

## 字体

提示符使用 Nerd Font 图标。仓库自带 `Hack Regular Nerd Font Complete Windows Compatible.ttf`，Linux 安装脚本会安装到当前用户的字体目录。

**如果通过 SSH 使用，请在你连接 SSH 的电脑上也安装这个字体，并把终端字体设为 `Hack NF`。** 只在 SSH 服务端安装字体不会改变客户端显示。使用正确字体后，才能完整显示 Powerlevel10k 图标和分隔符。

## 本机配置

`~/.zshrc` 顶部的加载块会先加载共享配置，再加载本机文件，最后执行已有的用户配置。代理、工具链、个人 PATH 等写入：

```bash
${EDITOR:-vi} ~/.config/cyfs-zsh/local.zsh
```

这个文件不在仓库中。不要在 Zsh 中直接加载包含 Bash 专用语法的 `.bashrc`，应把需要的变量和函数移到本机文件。脚本也会让登录 Zsh 加载原有的 POSIX `~/.profile`。

安装脚本会分离本机配置、优先使用自带 fzf、在用户目录创建 `fd` 链接、跳过已安装的系统依赖，并自动安装自带字体。原有配置会备份为 `~/.zshrc.bak.时间` 等文件，已有的 `.oh-my-zsh`、`.zplug`、`.fzf` 和 `.p10k.zsh` 会保留。

## 更新与恢复

```bash
cd ~/work/cyfs_zsh
git pull --ff-only
bash deploy.sh --no-chsh
exec zsh -l
```

恢复 Bash：

```bash
chsh -s /bin/bash
exec bash -l
```

需要移除启动配置时，删除 `~/.zshrc` 中 `# >>> cyfs_zsh >>>` 至 `# <<< cyfs_zsh <<<` 的加载块；原文件的备份位于用户目录。

第三方组件保留各自的许可。
