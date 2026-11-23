# 技术调研与架构决策

调研日期为 2026-11-23。

| 项目 | 调研结果与取舍 |
| --- | --- |
| [CompetiTest.nvim](https://github.com/xeluxee/competitest.nvim) | 已提供样例管理、独立运行与浮窗/分屏，并可接收浏览器扩展的数据。参考它的编辑器工作流，自己保存题面、评测历史及对拍记录。 |
| [Competitive Companion](https://github.com/jmerle/competitive-companion) | 浏览器扩展从用户访问的题页解析样例，向本地工具发送 JSON。洛谷解析依赖页面结构，发布记录中已有数次修复。首版无需扩展或本机 HTTP 监听。 |
| [online-judge-tools](https://github.com/online-judge-tools/oj) / [api-client](https://github.com/online-judge-tools/api-client) | 提供下载、测试、生成输入和由参考程序生成输出等 CLI 流程。其支持表未列出洛谷。借鉴分离输入生成、参考程序与输出比较的流程。 |
| [leetcode.nvim](https://github.com/kawre/leetcode.nvim) | 平台专用的列表、题面、测试和提交体验依赖 Plenary、Nui 等插件。oj.nvim 使用原生选择器、缓冲区、分屏和浮窗。 |
| [Neovim 0.10 API](https://github.com/neovim/neovim/blob/v0.10.0/runtime/doc/api.txt) / [Lua](https://github.com/neovim/neovim/blob/v0.10.0/runtime/doc/lua.txt) | 使用 `nvim_open_win`、结构化 Ex 命令和 `vim.ui`。终端适合交互调试。批量评测需要独立 stdin/stdout/stderr、输出上限及进程清理，使用 `vim.uv.spawn` 管理管道和退出。 |
| Linux 本地资源 | 通过一个由现有 C++ 工具链构建的小型 Linux 进程监督器，用进程组、`setrlimit` 和 `wait4` 获取可核对的指标和退出状态。进一步隔离应由 cgroup v2、命名空间及文件系统策略提供。Bubblewrap 初始化回环接口时被运行环境拒绝。离线验收使用 Linux 的用户与网络命名空间。 |

## 洛谷

- **官方来源**。开放平台给将洛谷作为远程评测源的 OpenApp 提供 NDJSON gzip 题库导出。Hydro 是官方列名的接入项目，其当前导入器印证了字段名（包括 `inputFormat`、`limits.time` 毫秒、`limits.memory` KiB、样例字符串对）。导出提供题面和可公开的样例，正式评测数据由洛谷保管。环境的 CDN DNS 解析失败，调研以官方文档和接入源码确认契约。 [开放平台评测文档](https://docs.lgapi.cn/open/judge/) · [Hydro 官方接入说明](https://docs.lgapi.cn/open/project/hydro) · [Hydro 导入源码](https://github.com/hydro-dev/luogu/blob/main/import.ts)
- **使用范围**。官方文档将导出列为 OpenApp 题库同步用途。公开浏览也不授予再发布题面、镜像题库或转授权的权利。用户可从其有权使用的导出文件按题号/题页 URL 导入，或手动整理自己有权保存的题面和样例。源码仓库只带少量原创说明、公开样例或明确标记为测试用的合成数据。 [洛谷用户协议](https://help.luogu.com.cn/ula/luogu)
- **正式提交**。OpenApp 用 HTTP Basic（OpenApp Token）进行鉴权，提交返回 request ID，随后可轮询（结果保留 1 小时），也支持 WebSocket 或回调。评测有额度限制。主站的人工提交需要登录并受比赛权限及验证码等限制。首版保留浏览器提交入口，持有有效 OpenApp 凭证和额度后才值得实现并验证 API 适配。 [API 鉴权](https://docs.lgapi.cn/open/api/auth) · [OpenAPI](https://docs.lgapi.cn/open/openapi) · [异步推送](https://docs.lgapi.cn/open/api/async-result) · [主站提交](https://help.luogu.com.cn/manual/luogu/problem/) · [更新日志](https://help.luogu.com.cn/release-note)
- **第三方与历史实现**。Companion 和 LPTP 都是第三方工具。网页内嵌数据、旧版 DOM 或旧前端数据对象会随页面更新而变化；Companion 可查到旧解析器失效及修复。未对第三方登录、前端取数或提交接口发请求，也没有证据据此断言某个旧 URL 目前完全不可用。 [Companion 发布记录](https://github.com/jmerle/competitive-companion/releases) · [当前洛谷解析器](https://github.com/jmerle/competitive-companion/blob/master/src/parsers/problem/LuoguProblemParser.ts) · [LPTP](https://github.com/kongfx/lptp)

## 实施顺序

1. 统一 Problem、校验配置、原子建立题目目录。先通过离线手动导入、C++ 编译、AC/WA/TLE/RE/CE、诊断与结果的最小验收。
2. 增加官方导出文件读取、题面和笔记、测试增补、异步对拍、取消和失败复现。补查边界行为与交互。
3. 用文件系统和 JSON 保留历史、失败输入与本地检索。扩展点保持简单，以供平台、运行语言和 checker 按需接入。
