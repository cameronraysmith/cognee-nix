# Cognee Frontend - Next.js web UI
#
# Uses bun to fetch all platform deps (--cpu="*" --os="*")
# This avoids HTTP/2 issues in prefetch-npm-deps and supports all platforms with single hash
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  nodejs_22,
  makeWrapper,
  geist-font,
}:
let
  nodejs = nodejs_22;
  sourceRoot = "source/cognee-frontend";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cognee-frontend";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "topoteretes";
    repo = "cognee";
    tag = "v${finalAttrs.version}";
    hash = "sha256-d9itqlCbEBJZilCJsBldUkg1Uy9GCor1cCemazLTJmo=";
  };

  inherit sourceRoot;

  # Fetch all platform deps using bun (FOD)
  node_modules = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src sourceRoot;

    nativeBuildInputs = [ bun ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      bun install \
        --cpu="*" \
        --os="*" \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules $out/
      runHook postInstall
    '';

    dontFixup = true;

    # TODO: outputHash to be replaced with real value after build cycle
    # captures node_modules contents for v1.1.0 (new Mantine UI deps).
    outputHash = lib.fakeHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    nodejs
    makeWrapper
  ];

  configurePhase = ''
    runHook preConfigure
    cp -r ${finalAttrs.node_modules}/node_modules .
    chmod -R u+w node_modules
    patchShebangs node_modules

    # Use local Geist fonts from nixpkgs instead of Google Fonts.
    # Google Fonts require network access which is not available in Nix sandbox.
    mkdir -p src/app/fonts
    cp ${geist-font}/share/fonts/opentype/Geist-Regular.otf src/app/fonts/
    cp ${geist-font}/share/fonts/opentype/GeistMono-Regular.otf src/app/fonts/

    # Replace next/font/google Geist + Geist_Mono imports with local OTF files.
    # Each Geist({...}) / Geist_Mono({...}) call spans multiple lines in
    # src/app/layout.tsx; pass the multi-line blocks verbatim to --replace-fail
    # so the `subsets: ["latin"]` field (invalid for next/font/local) is
    # dropped entirely rather than left dangling inside the new call.
    substituteInPlace src/app/layout.tsx \
      --replace-fail 'import { Geist, Geist_Mono } from "next/font/google";' 'import localFont from "next/font/local";' \
      --replace-fail 'const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});' 'const geistSans = localFont({
  src: "./fonts/Geist-Regular.otf",
  variable: "--font-geist-sans",
});' \
      --replace-fail 'const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});' 'const geistMono = localFont({
  src: "./fonts/GeistMono-Regular.otf",
  variable: "--font-geist-mono",
});'

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export NEXT_TELEMETRY_DISABLED=1
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/cognee-frontend

    cp -r .next $out/share/cognee-frontend/
    cp -r node_modules $out/share/cognee-frontend/
    cp -r public $out/share/cognee-frontend/
    cp package.json $out/share/cognee-frontend/

    # Remove build-time only SWC binaries to reduce closure size (~1GB)
    rm -rf $out/share/cognee-frontend/node_modules/@next/swc-*

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/cognee-frontend \
      --chdir "$out/share/cognee-frontend" \
      --set NODE_ENV production \
      --set PORT 3000 \
      --add-flags "$out/share/cognee-frontend/node_modules/.bin/next" \
      --add-flags "start"

    runHook postInstall
  '';

  meta = {
    description = "Next.js web UI for Cognee knowledge management";
    homepage = "https://github.com/topoteretes/cognee/tree/main/cognee-frontend";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ mulatta ];
    mainProgram = "cognee-frontend";
    platforms = lib.platforms.all;
  };
})
