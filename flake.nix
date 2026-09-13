{
  description = "nixos — paan 的 NixOS 26.05（QEMU/KVM + Intel 核显直通 + Hyprland/Caelestia）";

  inputs = {
    # 先钉在机器上原来那个 channel 的 revision，首次重建几乎不用重新下载；
    # 之后想升级用：sudo nix flake update --flake /etc/nixos
    nixpkgs.url = "github:NixOS/nixpkgs/a3116115851d68b8952a2a4221cc25a84e56b532";

    # 只为 Sunshine 这一个包引入 unstable 的包集：nixpkgs（含 unstable）里的 sunshine
    # 都还停在 2026.516.143833，其 wlr 抓屏会以 ~1 GB/min 泄漏 dma-buf 内存（实测：
    # 连上客户端约 4 分钟后 guest 内存见底、Hyprland 在 screencopy 路径 SEGV 进 safe
    # mode；停掉 sunshine 进程立即释放）。这里用 unstable 的包集去 callPackage
    # ./pkgs/sunshine.nix（本地 vendored 的包定义，升到上游 v2026.910.221003，
    # 含 2026-06 的 wlroots DMA-BUF modifier 修复与后续泄漏修复）。
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Caelestia 桌面外壳（Quickshell）。官方 NixOS 文档指定的装法就是 flake 引入。
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      user = "paan";
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
