# goyo.vim

无干扰写作模式 / Distraction-free writing for Vim。

本仓库是 [goyo.vim](https://github.com/junegunn/goyo.vim) 的 fork，将其核心实现
**用 Vim9script 重写**，并按 Vim 官方插件规范整理了目录结构、帮助文档与测试。

## 特性

* 内容窗口居中，四周由自动调整的填充窗口撑开；
* 隐藏状态栏、行号、colorcolumn 等界面元素；
* 支持以列数/百分比/偏移量指定内容尺寸；
* 进入 Goyo 后打开的窗口（`:help`、tag 跳转、`:copen` 等）会被约束在内容列内；
* 离开时保留 master 窗口实际显示的缓冲区；
* 严格保存/恢复全局选项与临时映射，退出后无残留。

## 环境要求

* Vim **9.1.0000+**，且编译包含 `+vim9script`；
* 也尝试兼容 Neovim（`--headless` 测试）。

## 安装

放入 `runtimepath` 即可（任意插件管理器皆可）：

```vim
set runtimepath+=/path/to/zen.vim
```

插件通过 `plugin/goyo.vim` 自动定义 `:Goyo` 命令。

## 使用

```vim
:Goyo            " 进入；再次执行退出
:Goyo 80x20      " 内容 80 列 x 20 行
:Goyo 50%x70%    " 百分比
:Goyo!           " 强制退出
```

完整的选项、回调、映射与事件说明见 `:help goyo`。

## 目录结构

```
plugin/goyo.vim     插件加载层：定义 :Goyo
autoload/goyo.vim   实现（Vim9script）
doc/goyo.txt        帮助文档
doc/tags            帮助标签（由 :helptags 生成）
test/               测试
test/run.sh         测试运行器
Makefile            常用任务
```

## 开发与测试

```sh
make test        # vim
make test-nvim   # nvim
make tags        # 重新生成 doc/tags
```

测试基于 Vim 内置的 `assert_*` 断言，零外部依赖，失败数即退出码，便于 CI。

## 许可

MIT，见 [LICENSE](LICENSE)。上游版权归 Junegunn Choi。
