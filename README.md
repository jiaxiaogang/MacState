# 自定义系统托盘显示系统状态：实时网速、CPU占用率、内存占用率、磁盘剩余空间。

<img width="369" height="121" alt="image" src="https://github.com/user-attachments/assets/51ae847e-4764-4aca-8ca0-61a7de88692c" />

* 运行：双击run.app运行
* 退出：pkill -f NetworkSpeedMenuBar
* 打包：swiftc NetworkSpeedMenuBar.swift -o NetworkSpeedMenuBar && cp NetworkSpeedMenuBar MacState.app/Contents/MacOS/
* 图标不生效问题：swiftc NetworkSpeedMenuBar.swift -o NetworkSpeedMenuBar && cp NetworkSpeedMenuBar MacState.app/Contents/MacOS/ && rm -rf MacState2.app && cp -R MacState.app MacState2.app && open MacState2.app
