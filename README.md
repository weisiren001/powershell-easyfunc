# powershell-easyfunc

一组可快速安装到 PowerShell Profile 的便捷函数。

## 快速开始

### 方法 1：一键网络安装（推荐）

直接运行以下命令，无需克隆仓库：

```powershell
iwr -useb https://raw.githubusercontent.com/weisiren001/powershell-easyfunc/main/web-install.ps1 | iex
```

> **说明**：该命令会从 GitHub 下载并执行安装脚本，自动获取最新的函数定义。
>
> **注意**：如果遇到执行策略限制，可能需要先运行 `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`。

### 方法 2：本地安装

1. 克隆或下载本仓库：

   ```powershell
   git clone https://github.com/weisiren001/powershell-easyfunc.git
   cd powershell-easyfunc
   ```

2. 运行安装脚本，将 easyfunc 区块写入所选 PowerShell Profile：

   ```powershell
   pwsh .\install.ps1
   ```

### 安装说明

- 脚本会列出常见 Profile（CurrentUser/AllUsers × CurrentHost/AllHosts 以及现有 profile 文件）。
- 通过菜单选择目标后，可选择安装/更新或卸载。
- 若目标位于 `Program Files`，脚本会提示以管理员身份重新运行。

安装完成后，重新打开 PowerShell 或 `.` 重新加载 Profile，即可使用上述函数。

## 常用操作

### 安装/更新

**网络方式**（推荐）：

```powershell
iwr -useb https://raw.githubusercontent.com/weisiren001/powershell-easyfunc/main/web-install.ps1 | iex
```

**本地方式**：

```powershell
pwsh .\install.ps1
```

按提示选择 Profile，选择 `I` 安装或更新 EasyFunc 块。

### 卸载

**本地方式**：

```powershell
pwsh .\install.ps1
```

选择相同的 Profile，选择 `U` 卸载。

## 工作原理

- `easyfunc.ps1` 定义了受管理的函数块，包裹在 `# <<<EASYFUNC_MANAGED_BLOCK_BEGIN_DO_NOT_EDIT_MANUALLY>>>` 与 `# <<<EASYFUNC_MANAGED_BLOCK_END>>>` 之间。
- `install.ps1` 适用于本地安装，会读取这段区块，写入或替换到选定的 Profile 文件中，同时支持卸载移除。
- `web-install.ps1` 是专门用于网络安装的引导脚本，无参数声明，可通过 `curl | iex` 管道执行，会自动从 GitHub 下载最新的 `easyfunc.ps1` 并完成安装。

## 开发

1. 修改 `easyfunc.ps1` 中的函数。
2. 测试后运行：

   ```powershell
   pwsh .\install.ps1 -SourceFile .\easyfunc.ps1
   ```

   以便把最新区块同步到 Profile。

欢迎提交 Issue 或 PR 以扩展更多便捷函数！

## 许可证

本项目采用 [MIT License](./LICENSE)。你可以自由使用、修改与分发，但请保留原作者版权声明。
