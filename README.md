### 一、项目说明：

##### 自定义系统托盘显示系统状态：

1. 实时网速
2. CPU占用率
3. 内存占用率
4. 磁盘剩余空间

<img width="369" height="121" alt="image" src="https://github.com/user-attachments/assets/51ae847e-4764-4aca-8ca0-61a7de88692c" />

### 二、使用说明：

* 使用方式：双击打开。
* 下载地址：<https://github.com/jiaxiaogang/MacState/releases/download/1.0/MacState.app.zip>
* 退出方式：点击任意图标，点退出。
* 自定方式：点击任意图标，点关闭。

### 三、开发命令：

* 运行：双击run.app运行
* 退出：pkill -f NetworkSpeedMenuBar
* 打包：swiftc NetworkSpeedMenuBar.swift -o NetworkSpeedMenuBar && cp NetworkSpeedMenuBar MacState.app/Contents/MacOS/
