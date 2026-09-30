systemd build

OkraLinux 的 systemd 包 编译时链上 libmount 和 libseccomp

为什么单独建仓库

之前那份 systemd 没链 libmount 所以 mount 单元全被 mask okra-init 得自己手写挂载
也没链 libseccomp 日志里一堆系统调用无法解析
这个仓库就是重新编一份带这两个库的

构建

在 actions 里手动触发 选架构 aarch64 用 arm runner x86_64 用普通 runner

产物在 Release 里 tag 是 packages

验证

构建日志会打印 systemd 和 systemctl 的 NEEDED 列表 看到 libmount 和 libseccomp 就算对
