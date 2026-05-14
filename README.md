* 运行：双击run.app运行
* 退出：pkill -f NetworkSpeedMenuBar
* 打包：swiftc NetworkSpeedMenuBar.swift -o NetworkSpeedMenuBar && cp NetworkSpeedMenuBar MacState.app/Contents/MacOS/
* 图标不生效问题：swiftc NetworkSpeedMenuBar.swift -o NetworkSpeedMenuBar && cp NetworkSpeedMenuBar MacState.app/Contents/MacOS/ && rm -rf MacState2.app && cp -R MacState.app MacState2.app && open MacState2.app
