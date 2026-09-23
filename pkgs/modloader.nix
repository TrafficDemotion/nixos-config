# modloader —— 在用户态把内核模块「补上未导出符号再加载」的小工具
# （shadichy/modloader，实现从 KernelSU 源码抽取）。
#
# 为什么必须用它、而不是直接 modprobe：
#   KernelSU 的模块引用了 27 个**没有导出**的内核符号（kallsyms_lookup_name、
#   kallsyms_lookup_size_offset、tasklist_lock、set_fs_pwd、seccomp_filter_release、
#   __x64_sys_setns、strncpy_from_user_nofault、__tracepoint_sched_process_exec …），
#   编成外部模块时 modpost 只能把它们标成 undefined（KBUILD_MODPOST_WARN=1 把错误降级
#   为警告），内核加载器遇到未定义符号会直接 `Unknown symbol` 拒绝。
#   modloader 读 /proc/kallsyms，把这些符号在 ELF 里直接 patch 成绝对地址
#   （SHN_ABS），然后调 init_module —— 所以它能加载普通 insmod 装不进去的模块。
#
# 注意：上游源码的 git 依赖（Kernel-SU/rustix，rev 4a53fbc）已在 GitHub 上 404，
# 源码构建走不通，所以这里取官方 release 的静态 musl 二进制（x86_64）。
# 换成别的版本时要重新算 hash：nix-prefetch-url --type sha256 <url>
{ lib, stdenv, fetchurl }:

stdenv.mkDerivation {
  pname = "modloader";
  version = "2.0.0";

  src = fetchurl {
    url = "https://github.com/shadichy/modloader/releases/download/v2.0.0/modloader-x86_64-musl";
    hash = "sha256-iE03K5kjFZ443BwxVicvPY53TQQ9+qdjk1KjuqMLNgc=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/modloader
    runHook postInstall
  '';

  meta = {
    description = "User-space kernel module loader that resolves non-exported symbols from kallsyms";
    homepage = "https://github.com/shadichy/modloader";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
