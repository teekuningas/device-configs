{ lib, makeWrapper, nodejs, github-copilot-cli }:

github-copilot-cli.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];
  postInstall = ''
    mkdir -p $out/libexec
    mv $out/bin/copilot $out/libexec/copilot
    makeWrapper $out/libexec/copilot $out/bin/copilot \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}
  '';
})