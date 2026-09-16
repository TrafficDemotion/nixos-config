{ lib, buildGoModule, fetchFromGitHub }:

# 终端屏保 / 环境可视化（drift）：上游有 flake，但它的 vendorHash 是占位符
# （作者自己注释 "Run nix build once; replace with the hash from the error"），
# 而且它的 flake 钉的是 nixos-unstable（多拉一整个 nixpkgs）。这里直接按同一份
# 参数写成本地 derivation，走我们自己的 nixpkgs。
buildGoModule rec {
  pname = "drift";
  version = "0.0.0-unstable-2026-09-10";

  src = fetchFromGitHub {
    owner = "phlx0";
    repo = "drift";
    rev = "4525768c8b7d706cc688956e328ed30aca8983e9";
    hash = "sha256-PEKVwtJGYgyaV31OUMDHbYqS948GqBZ1/gb/n12D3Fo=";
  };

  vendorHash = "sha256-xcSoDytK7cQrECa5PVoLunCG5im2YbOd8/0bclvTaq0=";

  # CGO_ENABLED 不在这里设：buildGoModule 自己会传（显式再写一遍会撞
  # "The `env` attribute set cannot contain any attributes passed to derivation"）。
  # 上游 flake 里那句 CGO_ENABLED = 0 是为了它的 unstable nixpkgs，这里不需要。

  # 与上游 flake.nix 的 ldflags 保持一致（version 用不到 self.shortRev，钉住 rev 就行）
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.commit=${src.rev}"
    "-X main.date=unknown"
  ];

  meta = with lib; {
    description = "Terminal screensaver and ambient visualiser";
    homepage = "https://github.com/phlx0/drift";
    license = licenses.mit;
    mainProgram = "drift";
  };
}
