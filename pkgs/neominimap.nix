{ lib, vimUtils, fetchFromGitHub }:

# neominimap.nvim —— Neovim 的代码缩略图（VSCode 那种右侧 minimap）。
# nixpkgs 里没有：钉住的 26.05（a3116115）与 nixpkgs-unstable 的 vimPlugins 下一共只有
# 老的 minimap-vim（两个包集都查过）。所以按 nixpkgs 自己生成插件时的写法
# （vimUtils.buildVimPlugin）本地 vendored 一份，rev 钉在上游 tag 上。
#
# 升级：改 rev / version / hash。拿 hash 的命令（不用先跑一次失败 build）：
#   nix-prefetch-url --unpack --type sha256 \
#     https://github.com/Isrothy/neominimap.nvim/archive/refs/tags/<tag>.tar.gz
#   nix hash convert --hash-algo sha256 --from nix32 --to sri <上面输出的 base32>
vimUtils.buildVimPlugin {
  pname = "neominimap.nvim";
  version = "3.16.0";

  src = fetchFromGitHub {
    owner = "Isrothy";
    repo = "neominimap.nvim";
    rev = "v3.16.0";
    hash = "sha256-EcV/mdleyopQsJ/t/Whl6Yf/2ORb9rnhHuc2Ue1E1Bw=";
  };

  # 上游依赖全是可选的（nvim-treesitter / gitsigns / mini.diff），本机有 treesitter，
  # 其它没有也不影响 —— 所以不需要写 dependencies。
  meta = with lib; {
    description = "A minimap for Neovim (tree-sitter based code overview)";
    homepage = "https://github.com/Isrothy/neominimap.nvim";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
