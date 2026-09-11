#!/bin/zsh

# Double-click this file in Finder to build, install, and launch AIWindow.
aiwindow_launcher_directory=${0:A:h}

"$aiwindow_launcher_directory/scripts/install_on_connected_iphone.sh"
aiwindow_launcher_status=$?

print
if (( aiwindow_launcher_status == 0 )); then
    print "AIWindow 已安装并启动。"
else
    print -u2 "AIWindow 安装未完成，请查看上面的错误信息。"
fi
print "按回车键关闭此窗口。"
read -r

exit "$aiwindow_launcher_status"
