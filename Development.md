## **一、欢迎**

感谢你对 NodeScriptKit 的兴趣！本指南将帮助你快速上手开发流程，提交代码并参与项目建设。无论你是修复 Bug、添加功能还是完善文档，我们都欢迎你的贡献。


## **二、环境搭建**


### **前置条件**



* **操作系统**：Linux（推荐 Debian、Ubuntu、CentOS 或 Alpine）。
* **权限**：需要 root 权限运行脚本。
* **工具**：
    * `bash`：核心脚本语言。
    * `curl` 和 `wget`：用于下载外部资源。
    * `git`：用于版本控制。


### **获取代码**

克隆仓库：

```
git clone git@github.com:NodeSeekDev/NodeScriptKit.git
cd NodeScriptKit
```



### **安装依赖**

运行以下命令安装基本依赖：

```
apt update && apt install -y curl wget git  # Debian/Ubuntu
yum install -y curl wget git               # CentOS
apk add curl wget git                      # Alpine
```

## **三、代码结构**


* **主文件**：`nodescriptkit.sh`（假设为你的脚本文件名）。
* **核心功能**：
    * `display_menu`：主菜单入口。
    * `sys_info`：系统信息查询。
    * `tcp_tune`：TCP 参数优化。
    * 更多模块见脚本注释。
* **外部资源**：部分功能依赖在线脚本（如 `bbr.sh`）。


## **四、开发规范**


### **命名规则**



* **函数名**：小写加下划线，如 `get_system_info`。
* **变量名**：清晰描述用途，如 `ipv4_address`。
* **颜色变量**：使用现有定义，如 `RED`、`GREEN`。

具体可阅读脚本 &lt;示例代码>


### **代码风格**

* **缩进**：使用 2 或 4 个空格（保持一致）。
* **注释**：关键功能需添加简要说明，例如：


* **函数名**：小写加下划线，如 `get_system_info`。
* **变量名**：清晰描述用途，如 `ipv4_address`。
* **颜色变量**：使用现有定义，如 `RED`、`GREEN`。

具体可阅读脚本 &lt;示例代码>


### **代码风格**
* **缩进**：使用 2 或 4 个空格（保持一致）。
* **注释**：关键功能需添加简要说明，例如：

```
# 获取系统运行时间
runtime=$(cat /proc/uptime | awk ...)
```
错误处理：使用 danger、success 等函数提示用户：

```
success "执行成功！"
danger "请以 root 权限运行脚本！"
```

### **提交要求**

* **单一目的**：每个 PR 解决一个问题或添加一个功能。
* **提交信息**：
    * 格式：`[类别] 描述`，如 `[Fix] 修复 IPv6 获取失败问题`。
    * 类别可选：`[Feat]`（新功能）、`[Fix]`（修复）、`[Docs]`（文档）等。

## **五、开发流程**

### **1. Fork 与分支**

1） Fork 仓库。

2). 创建功能分支，如：

```
git checkout -b feature/add-database-tool
```

### **2. 修改与测试**

- 基于&lt;示例代码>规范，编辑脚本，添加或优化功能。

- 本地测试：

```
nsk
```

- 示例：运行 检查系统信息是否正常输出。
- 实机测试：参考 &lt;测试方法>

### **3. 提交代码**

1. 提交更改：

```
git add .
git commit -m "[Feat] 添加数据库管理工具"
```

2. 推送到远程：

```
git push origin feature/add-database-tool
```

### **4. 提交 Pull Request**

- 在 GitHub 上创建 PR，描述你的改动和测试结果。
- 等待维护者审核。


## **六、测试方法**

* **环境**：建议使用虚拟机（如 VirtualBox）或 VPS。
* **步骤**：
    1. 运行完整脚本，检查菜单功能。
    2. 测试特定模块，如 `nsk -> 选择分类，测试最终结果符合预期`。
    3. 检查错误日志，确保无异常退出。
* **兼容性**：在不同系统（Debian、CentOS）上验证


## **七、已知问题**
* 部分功能依赖网络，可能因连接问题失败。

该部分逐步补充...


## **八、获取帮助**

* **社区**：加入 [Telegram 频道](https://t.me/NodeSelect) 或 GitHub Discussions。

让我们一起让 NodeScriptKit 更强大！
