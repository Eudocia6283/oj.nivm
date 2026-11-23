# oj.nvim

oj.nvim 是本地优先的 Neovim 算法训练插件。用同一目录保存题面、C++ 解法、测试、笔记和评测历史。导入题目后，可以离线读题、运行样例、自定义测试和对拍。

需要 **Linux、Neovim 0.10+、GCC 或 Clang 的 C++ 编译工具链**。默认编译器为 `g++`，默认标准为 C++20。读取压缩导出需要 `gzip`，主动同步需要 `curl`，Python 生成器或 checker 才需要 `python3`。无需额外的 Neovim UI 插件。

## 安装

Arch Linux 上，系统缺少基础依赖时可在 Fish 中执行：

```fish
sudo pacman -S --needed neovim gcc gzip curl python
```

在 lazy.nvim 的插件列表中加入以下规格。将 `dir` 改成实际的源码目录。省略 `cmd` 可以随 Neovim 启动加载。

```lua
{
  dir = vim.fn.expand("~/Projects/oj"),
  name = "oj.nvim",
  main = "oj",
  cmd = {
    "OJOpen", "OJNew", "OJImport", "OJLuoguSync", "OJList", "OJSearch",
    "OJStatement", "OJNotes", "OJRun", "OJTest", "OJTestAdd", "OJTestEdit",
    "OJStress", "OJStressConfig", "OJStressStop", "OJStop", "OJReplay",
    "OJResults", "OJHistory", "OJSubmit",
  },
  opts = {
    root = "~/Algorithms",
    statement = "float",
  },
}
```

也可以把源码目录加入 `runtimepath`，按需调用 `require("oj").setup({...})`。从源码目录临时试用：

```fish
nvim -u NONE -i NONE --cmd 'set runtimepath^=.' -c 'runtime plugin/oj.lua'
```

## 第一道题

在源码目录启动 Neovim 后，使用仓库提供的 P1001 手动导入示例。示例使用自行撰写的简要题意和公开样例 `20 30 → 50`。 [P1001 题页](https://www.luogu.com.cn/problem/P1001) · [公开样例出处](https://www.luogu.com/article/cfz1leh2)

```vim
:OJImport luogu P1001 tests/fixtures/p1001.json
:OJStatement
```

按 `q` 回到 `main.cpp`，写入解法并保存，再运行样例。

```cpp
#include <iostream>

int main() {
    long long a, b;
    if (!(std::cin >> a >> b)) return 1;
    std::cout << a + b << '\n';
}
```

```vim
:write
:OJTest
:OJResults
```

评测完成后 Neovim 显示通知。用 `:OJResults` 打开详细结果，或用 `:OJHistory` 选择历史记录。**本地 AC 表示通过本次所选的本地测试。正式结果以平台评测为准。**

## 命令与按键

下表中的 `题目` 可以写成 `luogu P1001`、`P1001`、`1001` 或洛谷 HTTPS 题页 URL。评测、笔记等命令从题目工作区中的当前文件或 OJ 面板识别题目。

| 命令 | 作用 |
| --- | --- |
| `:OJOpen 题目` | 打开已有解法。如果题目还未缓存，尝试从已配置的本地导出导入。 |
| `:OJNew 题目` | 建立空工作区，生成 C++ 模板、空题面和笔记。 |
| `:OJImport 题目 [文件]` | 从手动 JSON、`.ndjson` 或 `.ndjson.gz` 导入单题。省略文件时使用已配置的导出。 |
| `:OJLuoguSync` | 在符合开放平台使用范围时，主动下载并验证官方导出。 |
| `:OJList` / `:OJSearch [文本]` | 列出已导入题目，或搜索其中的题号、标题、难度、标签和题面文本。 |
| `:OJStatement` / `:OJNotes` | 查看 Markdown 题面或在分屏编辑笔记。 |
| `:OJRun [输入文件]` | 编译并单独运行解法。可输入文件，结果显示退出状态和输出。 |
| `:OJTest [名称]` | 编译已保存的 `main.cpp`，测试全部或指定的 `.in/.out` 对，例如 `:OJTest sample1`。 |
| `:OJTestAdd 名称 [输入文件 期望输出文件]` | 从两个文件导入自定义测试。省略文件时创建空白输入和期望输出，请填写并保存。 |
| `:OJTestEdit 名称` | 在分屏打开现有测试的两个文件。 |
| `:OJStressConfig` | 编辑当前题目的 `settings.json`。 |
| `:OJStress [次数 [种子]]` | 编译并比较待测程序与参考程序，在首个运行错误或比较失败时停止。 |
| `:OJStressStop` / `:OJStop` | 取消对拍，或取消当前 OJ 任务。 |
| `:OJReplay [记录 ID]` | 用归档输入和参考输出测试当前 `main.cpp`。省略 ID 时使用最新记录。 |
| `:OJResults [记录 ID]` / `:OJHistory` | 查看某次评测，或挑选历史评测。 |
| `:OJSubmit` | 在系统浏览器打开洛谷提交入口。随后在洛谷登录并手动提交。 |

面板内用 `q` 关闭窗口。在结果列表中，`]e` 和 `[e` 定位失败项，`Enter` 查看详情，`d` 查看输出差异，编译失败时 `c` 打开 quickfix 诊断。插件仅在自己的面板中安装按键。可自行绑定常用命令：

```lua
vim.keymap.set("n", "<leader>ot", "<cmd>OJTest<cr>", { desc = "运行 OJ 测试" })
vim.keymap.set("n", "<leader>or", "<cmd>OJResults<cr>", { desc = "查看 OJ 结果" })
```

## 洛谷题目导入

**手动导入**适合私人学习、离线环境及自己有权使用的题面。可按照 [JSON 示例](tests/fixtures/p1001.json) 整理。只有 `title` 必填。描述使用 Markdown，`time_limit_ms` 的单位为毫秒，`memory_limit_kib` 的单位为 KiB，样例是 `{ "input": "...", "output": "..." }` 数组。使用 JSON 的 `\n` 保留换行。缺少公开样例时可以保留空数组，后续用自己的用例测试。导入会校验题号、字段、大小、UTF-8 和样例配对。

**官方导出**是洛谷面向将其作为远程评测源的 OpenApp 提供的题面数据。若符合该使用范围，可执行 `:OJLuoguSync`，将官方文件放进工作区的 `config/luogu-open.ndjson.gz`。也可以把有权使用的导出路径配置为 `luogu.dataset`，或显式从文件导入：

```vim
:OJImport luogu P1001 /home/you/我的题库/latest.ndjson.gz
:OJOpen https://www.luogu.com.cn/problem/P1001
```

文件名中的普通空格可以直接写在 `:OJImport` 的文件参数中。双路径的 `:OJTestAdd` 请用反斜杠转义各路径内的空格。洛谷导出中的测试点限制数组取最大值供阅读，本地实际限制以插件配置为准。题面和公开样例的缓存及再使用遵守各自权利范围。 [开放平台评测文档](https://docs.lgapi.cn/open/judge/) · [官方接入项目导入器](https://github.com/hydro-dev/luogu/blob/main/import.ts) · [洛谷用户协议](https://help.luogu.com.cn/ula/luogu)

题号和 URL 都用来定位导出中的记录。未缓存时，`:OJOpen` 只访问本地导出。导入会保护已存在的同题目录，手动创建空工作区前可先选择导入。题面按 Markdown 显示并保留 LaTeX 源文和代码块，公式与远程图片保持文本形式。正式隐藏测试不包含在本地工作区。

洛谷开放平台通过 OpenApp Token 进行 Basic 鉴权，提交与轮询结果需要可用的 OpenApp 和评测配额。本版默认使用浏览器入口，无需在 Neovim 中配置 Cookie 或 Token。调研及第三方方案比较见 [技术调研](docs/research.md)。 [API 鉴权](https://docs.lgapi.cn/open/api/auth) · [正式提交 API](https://docs.lgapi.cn/open/openapi)

## 对拍与复现

1. 在题目目录中保存 `main.cpp`、`brute.cpp`、`gen.cpp` 或 `gen.py`。
2. 生成器从第一个命令行参数获取整数种子，在 stdout 输出一组输入。两份解法从 stdin 读取同一组数据。种子逐轮加一，按 32 位无符号范围回绕。
3. 运行 `:OJStress 1000 123456`。一轮全部成功才计为通过。每 250 轮有一次进度通知。
4. 遇到差异时，`:OJResults` 可查看比较和子进程状态，记录包含该轮种子，以及实际产生的输入、双方输出与 stderr。直接运行结果中显示的 `:OJReplay <ID>`，使用归档输入与参考输出重新测试当前代码。也可以用结果给出的 `:OJStress 1 <种子>` 重跑该轮生成器和两份程序。源代码或生成器改动会影响重跑。

`auto` 按题目目录优先、共享生成器目录其次的顺序查找，每个目录优先 `gen.cpp` 再找 `gen.py`。需要长期固定一项时，可运行 `:OJStressConfig` 设置 `iterations`、`seed`、`generator` 或 `compare`。

文本比较支持 `lines`（默认，统一 CRLF，忽略行尾空格和末尾多余换行）、`tokens`（连续空白统一为分隔符）和 `exact`（逐字节比较）。对特殊判题可在可信 Neovim 配置中设置 `checker` 为 argv 列表。插件在末尾追加三个绝对路径，依次是输入、参考输出、待测输出。退出 0 为通过，退出 1 为答案不符，其他退出码、信号或超时为 checker 错误。checker 同样受运行限制。

## 工作区与配置

```text
~/Algorithms/
├── problems/luogu/P1001/
│   ├── main.cpp
│   ├── problem.md
│   ├── metadata.json
│   ├── notes.md
│   ├── tests/
│   │   ├── sample1.in
│   │   └── sample1.out
│   ├── settings.json           # 可选，题目级配置
│   └── history/               # 有评测后创建
├── templates/
├── generators/
└── config/
```

下面列出常用选项和默认值。只传需要修改的项。目录选项是根目录下互不相同的单段名称，可含空格和 Unicode。在模板目录放入配置对应的文件即可自定义新建 `main.cpp` 的内容。

```lua
require("oj").setup({
  root = "~/Algorithms",
  paths = { problems = "problems", templates = "templates", generators = "generators", config = "config" },
  template = "cpp.cpp",
  cpp = { compiler = "g++", flags = { "-std=c++20", "-O2", "-Wall", "-Wextra", "-fdiagnostics-color=never" } },
  python = "python3",
  limits = { wall_ms = 2000, cpu_seconds = 0, memory_mib = 512, output_kib = 1024, compile_ms = 30000 },
  stress = { iterations = 1000, seed = 1, generator = "auto" },
  compare = "lines",
  statement = "float", -- 或 "split"
  luogu = { timeout_ms = 120000 }, -- 可另设 dataset = "/path/to/latest.ndjson.gz"
  -- checker = { "python3", "/absolute/path/checker.py" },
})
```

改用 C++17 时，将编译参数中的 `-std=c++20` 换成 `-std=c++17`。编译参数按数组逐项传递。每个 Neovim 实例同时运行一个 OJ 任务。常规测试单次至多读取 256 对用例，每个输入或期望输出文件上限为 4 MiB。评测结果面板会截断长文本，对拍失败目录保存捕获范围内的原始字节。

### 运行资源

- **墙钟时间**是从被监督进程启动到退出或被判定超时的经过时间，包含等待输入、睡眠和调度等待。
- **CPU 时间**取 Linux `wait4` 的用户态与内核态 CPU 用时。可用 `cpu_seconds` 设置 Linux 的整秒 CPU 限制，0 表示关闭。
- **峰值 RSS**取 Linux `wait4` 的 `ru_maxrss`，以 KiB 显示。它是内核为被等待进程记录的峰值，不能视为整个进程树同时占用的总内存。 `memory_mib` 限制单进程虚拟地址空间，0 表示关闭。分配失败通常会表现为 RE，无法仅凭退出码确定 MLE。
- 每个子进程用独立的运行目录、进程组、有限的 stdout/stderr 捕获和 Linux 资源限制。监督器终止并回收普通派生进程。它可以限制可信本地代码的资源消耗，但不提供完整安全沙箱。解法、生成器和 checker 仍以本机用户权限运行，能访问系统允许的文件和网络。只执行自己信任的代码。

主要状态包括 `AC`、`WA`、`TLE`、`RE`、`CE`、`OLE`（超出输出限制）与 `ERROR`（文件、运行环境、生成器、参考程序或 checker 错误）。失败诊断会保留实际退出码或信号。

## 验证

需要 `nvim`、`g++`、`gzip`、`python3` 和 `make`。测试使用临时题库。当前已在 Linux / Neovim 0.12.6 运行，并验证 lazy.nvim 按命令加载与 Clang C++17。0.10 基线依据其公开 API，仍待用 0.10 二进制实跑。

```fish
make test
# Linux 上允许非特权用户命名空间时，可另跑完整离线验收
unshare -Urn -- make test
```

手动复现可从上一节的 P1001 开始：

1. 样例运行得到 AC。把 `a + b` 改成 `a + b + 1`，保存并重测。用 `]e`、`d` 检查 Diff。
2. 添加 `#include <unistd.h>`，把输出语句改成 `for (;;) pause();`，保存后重测，应得到 TLE。再把输出表达式换成未定义的变量，应得到 CE。用 `:OJResults` 后按 `c` 检查源码位置。
3. 在 Fish 中把 `p1001` 设为实际工作区目录，拷贝参考解与生成器。恢复上面的正确解法，然后运行 `:OJStress 1000 123456`。

   ```fish
   set p1001 "$HOME/Algorithms/problems/luogu/P1001"
   cp -n tests/fixtures/brute.cpp "$p1001/brute.cpp"
   cp -n tests/fixtures/gen.cpp "$p1001/gen.cpp"
   ```

4. 再制造加一的错误，运行 `:OJStress 1000 123456` 并用 `:OJResults` 检查首轮失败，从面板抄下 `:OJReplay` 命令运行。恢复正确解法后可在长对拍期间继续编辑其他缓冲区，执行 `:OJStressStop` 检查取消。
5. 断开网络后重新启动 Neovim，执行 `:OJOpen P1001`、`:OJStatement` 和 `:OJTest`。题面和本地测试都来自工作区。

自动化另覆盖 Unicode 和空格路径、解包损坏、模拟下载与缓存回滚、异常参数、配置、符号链接、子进程回收、评测时编辑、CPU/地址空间/输出限制、峰值 RSS、Python 生成器与 checker。

## 扩展接口

可信 Lua 配置可调用 `require("oj.providers").register(name, adapter)`。Provider 实现 `identify(ref)` 和 `source_url(id)`。也可提供 `has_dataset(config)`、异步的 `from_dataset(task, config, id, path)` 和 `submission_url(id)`。导入返回归一化的 Problem，不操作编辑器窗口。

原生 `User OJTaskStart` 和 `User OJTaskFinish` 事件通过 `event.data.kind` 提供任务类型。结束事件还提供 `completed`、`cancelled` 或 `error`，评测判定见结果记录。

## 当前范围与下一阶段

已交付洛谷本地 Provider、工作区、编译评测、种子对拍、失败复现、题目搜索与个人笔记。正式 OpenApp 提交与结果查询、其他平台适配器、交互题、代码快照和输入缩减留待后续。官方 CDN 的真实下载在本开发环境受 DNS 限制，导出格式和本地导入通过测试夹具验证。

下一阶段优先在 Neovim 0.10 和获准的 OpenApp 环境补做真实导出与提交验证，其次加入 Linux cgroup v2 或命名空间隔离后端。将现有 Provider 接口用于其他平台之前，先逐一确认授权获取与提交方式。

源码按 [MIT License](LICENSE) 开放。
