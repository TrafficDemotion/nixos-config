# KernelSU-Next（Waydroid 版）宿主侧声明式配置                       2026-09-29
#
# 为什么需要这些东西：Waydroid 的 single-window 模式把 Android 跑在 LXC 容器里，
# 容器里的 init 需要 root，我们给它 KernelSU（上游 incapdns/KernelSU-Next-Waydroid
# 的 waydroid-dev 分支）。它的模型是：
#   * 一个**外挂**的 kernelsu.ko —— 不在宿主内核里编，靠 modloader 注入，所以既
#     不受 NixOS 内核模块签名限制，也不需要导出符号；代价是 ko 必须与宿主内核
#     vermagic 严格一致，所以这里用 Nix 按当前内核现编（内核一升级就自动重编）。
#   * lxc.hook.pre-start 在容器 init 之前加载模块；lxc.hook.post-stop 触发一个
#     oneshot + timer，在容器**完全退出**后安全卸载（KSU 的 x86 inline hook 必须先
#     解除全局回调、等引用排空才能 rmmod，否则会执行到已释放的代码页）。
#   * Waydroid 的 lxc seccomp profile 里要删掉那条重启类系统调用的拒绝项
#     （KSU 的 magic-call 传输要用它）。这一步也在 configure 里做。
#
# 不在本模块内的前置条件：宿主内核命令行必须有 `ibt=off`。KSU 的 x86 inline hook 与
# CONFIG_X86_KERNEL_IBT=y 冲突（否则开机 kernel BUG at arch/x86/kernel/cet.c:133，
# Android 卡在 zygote restart 循环），而 IBT 没有运行时开关。
#
# 部署位置：所有文件进 /etc/kernelsu-next-waydroid（/usr/lib 下不留任何手工文件）。
#
# 回滚：删掉 configuration.nix 里的 import 与该 enable 开关，然后手工清掉
# /var/lib/waydroid/lxc/waydroid/config 里的两条 lxc.hook.* 行 —— 否则 lxc 会去执行
# 已不存在的 hook 并拒绝启动容器。

{ config, lib, pkgs, ... }:

let
  cfg = config.services.kernelsu-waydroid;
  kernel = config.boot.kernelPackages.kernel;
  modDir = kernel.modDirVersion;

  # 外挂 ko：从上游源码现编（KCFLAGS 补一个上游缺的 #include，见 skill nixos-waydroid）
  kernelsuModule = pkgs.stdenv.mkDerivation {
    pname = "kernelsu-next-waydroid";
    version = "2734bc6";
    src = pkgs.fetchFromGitHub {
      owner = "incapdns";
      repo = "KernelSU-Next-Waydroid";
      rev = "2734bc67941db50c5b9d6dea1d172d8412628349";
      hash = "sha256-ft1oZhlUwZ4LZZwfh0y7DvEtfAr0+3PxBMm/p+M1Mac=";
    };
    nativeBuildInputs = with pkgs; [ bc perl flex bison openssl pahole kmod rsync ];
    buildInputs = [ kernel.dev ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      # 注意：kbuild 对 M= 外部模块会把 $(src) 求值成 `.`，上游 Kbuild 的
      # KSU_KERNEL_DIR 因此算到内核源码树上去 ⇒ 必须显式传 src=<模块目录>。
      # 工具链用宿主内核同款 gcc（NixOS 内核就是 gcc 编的）。
      # 版本号：Kbuild 用 `30000 + git rev-list --count HEAD`，而 Nix 从 tarball
      # 编译时没有 .git ⇒ 退化成 fallback(1) 报 30001，管理器
      # (MINIMAL_SUPPORTED_KERNEL=33188) 会因此把模块管理 UI 整个关掉。
      # 3271 = waydroid-dev(2734bc6) 的真实提交序数 ⇒ 33271，与上游 manager
      # 33267 同代；KSU_GIT_VERSION_VALID=1 才是那个开关。
      make -C "${kernel.dev}/lib/modules/${modDir}/build" \
        M="$PWD/kernel" \
        src="$PWD/kernel" \
        modules \
        CONFIG_KSU=m \
        CONFIG_KSU_NON_ANDROID=y \
        CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y \
        CONFIG_KSU_SELINUX=n \
        KBUILD_MODPOST_WARN=1 \
        KSU_GIT_VERSION=3271 \
        KSU_GIT_VERSION_VALID=1 \
        KSU_GIT_TAG=waydroid-dev-2026.08.19-r4 \
        KCFLAGS="-include linux/rwsem.h" \
        -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 kernel/kernelsu.ko "$out/kernelsu.ko"
      runHook postInstall
    '';
  };

  # modloader：加载带未导出符号的内核模块（上游 release，musl 静态）
  modloader = pkgs.fetchurl {
    url = "https://github.com/shadichy/modloader/releases/download/v2.0.0/modloader-x86_64-musl";
    hash = "sha256-iE03K5kjFZ443BwxVicvPY53TQQ9+qdjk1KjuqMLNgc=";
  };

  # 组装 /etc/kernelsu-next-waydroid：上游脚本把安装前缀硬编码成
  # /usr/lib/kernelsu-next-waydroid，这里统一改写成 /etc/kernelsu-next-waydroid
  # （连 ko 的搜索根 /usr/lib/modules 一起改），/usr/lib 下就不留任何东西。
  bundle = pkgs.runCommand "kernelsu-next-waydroid-bundle" { } ''
    mkdir -p $out/modules/${modDir}/updates
    cp -a ${./scripts}/. $out/
    chmod -R u+w $out
    # 只处理文件：$out 里还有 modules/ 目录，substituteInPlace 不能吃目录
    for f in $out/*; do
      if [ -f "$f" ]; then
        substituteInPlace "$f" \
          --replace-warn /usr/lib/kernelsu-next-waydroid /etc/kernelsu-next-waydroid \
          --replace-warn /usr/lib/modules /etc/kernelsu-next-waydroid/modules \
          --replace-warn /usr/lib/systemd/system/kernelsu-waydroid-unload.service /etc/systemd/system/kernelsu-waydroid-unload.service \
          --replace-warn /usr/lib/systemd/system/kernelsu-waydroid-unload.timer /etc/systemd/system/kernelsu-waydroid-unload.timer
      fi
    done
    install -m755 ${modloader} $out/modloader
    install -m644 ${kernelsuModule}/kernelsu.ko $out/modules/${modDir}/updates/kernelsu.ko
    install -m644 ${./uts-identity.conf} $out/uts-identity.conf
  '';
in
{
  options.services.kernelsu-waydroid.enable =
    lib.mkEnableOption "KernelSU-Next host support for the Waydroid LXC container";

  config = lib.mkIf cfg.enable {
    environment.etc."kernelsu-next-waydroid".source = bundle;

    # 容器完全退出后安全卸载模块
    systemd.services.kernelsu-waydroid-unload = {
      description = "Safely reconcile KernelSU unload after Waydroid teardown";
      after = [ "waydroid-container.service" ];
      path = with pkgs; [ coreutils util-linux procps lxc bash ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/kernelsu-next-waydroid/unload";
      };
    };

    systemd.timers.kernelsu-waydroid-unload = {
      description = "Retry pending KernelSU Waydroid teardown";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitInactiveSec = "2s";
        AccuracySec = "250ms";
        Unit = "kernelsu-waydroid-unload.service";
      };
    };

    # hook 是在 waydroid-container.service 的环境里被 lxc 调用的，确保它要的命令可见
    systemd.services.waydroid-container.path =
      with pkgs; [ coreutils kmod zstd xz gzip util-linux procps ];

    # Waydroid 每次起容器都会重写 /var/lib/waydroid/lxc/waydroid/config（我们的
    # hook 行会被抹掉），所以注册必须在**每次容器启动前**做，不能只做一次。
    systemd.services.waydroid-container.preStart = lib.mkAfter ''
      /etc/kernelsu-next-waydroid/configure || true
    '';
  };
}
