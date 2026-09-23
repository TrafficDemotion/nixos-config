# KernelSU（supechicken 的 waydroid 分支）编成宿主内核模块，供 Waydroid 用。
#
# 为什么是这个分支、而不是官方 tiann/KernelSU 或 SukiSU-Ultra：
#   Waydroid 是 LXC 容器，**与宿主共享内核**（NixOS 的 6.18.48），所以 Android 里的
#   root 方案必须在宿主内核侧实现。官方 KernelSU 至今没有非 Android 宿主的支持
#   （上游 issue #2791 仍 open：Waydroid 下 LKM 路线被认为「需要 massive changes」），
#   SukiSU-Ultra 的 Kconfig 里也没有对应开关，而且它的内核代码直接假设
#   「宿主 PID 1 就是 Android init」（hook/tp_marker.c: is_init = t->pid == 1），
#   在 Waydroid 里宿主 PID 1 是 systemd，标记链是断的。
#   supechicken（Waydroid 核心开发者）的 waydroid 分支专门补了这块：
#     · CONFIG_KSU_NON_ANDROID —— Kconfig 注释原文 "Consider enabling this when
#       targetting Waydroid"，作用是关掉 PID=1 检查，并改为用 namespace 相对 PID
#       （task_pid_vnr）识别容器里的 Android init（exec /system/bin/init 时打标记）。
#     · CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER —— x86_64 上运行期内核 syscall
#       dispatcher 已被加固（间接跳转改成直接分支），不 patch 的话 KernelSU 的
#       syscall hook 不生效；该选项让它在运行期动态 patch dispatcher（KernelSU 3.2.6+
#       的官方机制）。
#
# 编译要点（都在 buildPhase 里）：
#   · out-of-tree 构建：make -C <内核 dev 输出>/lib/modules/<ver>/build M=$PWD/kernel
#     NixOS 的内核 dev 输出自带 build 树（含 .config / Module.symvers / scripts），
#     source -> ../source 指向完整源码树，编译外部模块够用。
#   · KBUILD_MODPOST_WARN=1：把未导出符号的 modpost 错误降成警告（见 modloader.nix
#     的说明），编出来的 .ko 里那些符号保持 undefined，由 modloader 在加载时补。
#   · KSU_GIT_VERSION=2601 + KSU_GIT_VERSION_VALID=1：把内核侧版本钉成 32601
#     （= 30000 + 2601），与官方管理器 APK v3.3.0 (32601) 对齐。分支比官方 3.3.0
#     tag 多 7 个 commit，不钉的话算出来是 32608，管理器会报
#     "Manager version and KernelSU driver version mismatch" 红条。
#     另外 Nix 构建沙箱里没有 .git，Kbuild 的 git 检测必然失败，所以这两个值必须
#     从命令行传（Kbuild 里 `ifdef KSU_GIT_VERSION_VALID` 那段）。
#   · CONFIG_KSU_SELINUX=n：不依赖宿主内核的 SELinux 内部头（/security/selinux 在
#     dev 输出里不完整）。代价：管理器里 "SELinux status: Disabled"，依赖 SELinux
#     域的隐藏类功能用不了。要开就把 n 改 y（宿主 CONFIG_SECURITY_SELINUX=y）。
#
# 升级流程：改 rev / KSU_GIT_VERSION（=30000 之外的 git commit 数）→ 重算 src hash
# （nix-prefetch-url --unpack --type sha256 <rev 的 tarball>）→ rebuild。
{ lib, stdenv, kernel, fetchFromGitHub }:

let
  # 内核侧上报的版本号 = 30000 + 下面的数字，必须与所用的管理器 APK 版本一致。
  ksuGitVersion = 2601;
in
stdenv.mkDerivation {
  pname = "kernelsu-waydroid";
  version = "3.3.0-32601";

  src = fetchFromGitHub {
    owner = "supechicken";
    repo = "KernelSU";
    # 分支 waydroid-experimental（2026-08-28），AUR kernelsu-dkms 用的同一份。
    rev = "fde078c9e87a9bc2d30c81957c82a05a7120886c";
    hash = "sha256-hPVxprNEFI6XNR101uIrKLDUXOcEVAR57BqiUI7Twc4=";
  };

  # 内核模块不能用 nix 的默认 hardening 标志
  hardeningDisable = [ "all" ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild

    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/kernel modules \
      CONFIG_KSU=m \
      CONFIG_KSU_NON_ANDROID=y \
      CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y \
      CONFIG_KSU_SELINUX=n \
      CONFIG_KSU_DEBUG=n \
      KBUILD_MODPOST_WARN=1 \
      KSU_GIT_VERSION=${toString ksuGitVersion} \
      KSU_GIT_VERSION_VALID=1

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 kernel/kernelsu.ko \
      $out/lib/modules/${kernel.modDirVersion}/extra/kernelsu.ko
    runHook postInstall
  '';

  meta = {
    description = "KernelSU kernel module for Waydroid (non-Android host, x86_64 LKM)";
    homepage = "https://github.com/supechicken/KernelSU";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
