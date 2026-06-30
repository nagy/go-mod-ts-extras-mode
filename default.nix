{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs ? pkgs.emacs,
  emacsPackages ? emacs.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
}:

melpaBuild {
  pname = "go-mod-ts-extras-mode";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  emacs = emacs.pkgs.withPackages
    (epkgs: [ epkgs.treesit-grammars.with-all-grammars ]);

  turnCompilationWarningToError = true;

  meta = {
    description = "pkg.go.dev extras for go-mod-ts-mode";
    longDescription = ''
      A minor mode that enhances go-mod-ts-mode buffers with
      pkg.go.dev URL detection and browsing.  Module paths inside
      require and replace directives are underlined, thing-at-point
      returns their pkg.go.dev URLs, and RET opens them in a browser.
    '';
    license = lib.licenses.agpl3Plus;
    homepage = "https://github.com/nagy/go-mod-ts-extras-mode";
    maintainers = with lib.maintainers; [ nagy ];
    platforms = lib.platforms.unix;
  };
}
