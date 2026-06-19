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
}:
let
  nodejs = nodejs_22;
  sourceRoot = "source/cognee-frontend";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cognee-frontend";
  version = "1.1.2";

  src = fetchFromGitHub {
    owner = "topoteretes";
    repo = "cognee";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ef908AH6QvBLvMxR+aRy4cgK1HIpqchCquQSSJ24AWk=";
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

    outputHash = "sha256-9Nd8ifQ8i4goporh4tcw3AgW36WmZ/tuXM+J2Hmc1g8=";
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

      # Bypass `tsc` type-checking during `next build`. Upstream cognee-frontend
      # carries a number of TypeScript errors (CopyApiKeyButton apiKey shape
      # mismatch, unused @ts-expect-error directives, etc.) that the upstream
      # dev workflow tolerates but `next build` rejects in strict mode. Rather
      # than chase each error with a fragile substituteInPlace, we opt into
      # `typescript.ignoreBuildErrors` in next.config.{ts,mjs}.
      substituteInPlace next.config.ts \
        --replace-fail 'const nextConfig: NextConfig = {' 'const nextConfig: NextConfig = {
    typescript: { ignoreBuildErrors: true },'
      substituteInPlace next.config.mjs \
        --replace-fail 'const nextConfig = {}' 'const nextConfig = { typescript: { ignoreBuildErrors: true } }'

      # Rebind the build-time-inlined NEXT_PUBLIC_LOCAL_API_URL fallback per file.
      # NEXT_PUBLIC_* is inlined at build time and an empty string is falsy, so
      # the runtime env cannot reach these `||` defaults; the fallback literal is
      # the only build-time lever. Client fetch bases become same-origin ("") so
      # the browser issues /api/... requests under the serving vhost; the two
      # files that render a copyable backend URL keep an absolute public origin.
      for f in \
        src/modules/instances/localFetch.ts \
        src/modules/tenant/LocalProvider.tsx \
        "src/app/(auth)/local-login/partials/LocalSignInForm.tsx" \
        src/modules/users/getLocalUser.ts; do
        substituteInPlace "$f" \
          --replace-fail \
            'process.env.NEXT_PUBLIC_LOCAL_API_URL || "http://localhost:8000"' \
            'process.env.NEXT_PUBLIC_LOCAL_API_URL || ""'
      done

      for f in \
        "src/app/(app)/api-keys/ApiKeysPage.tsx" \
        "src/app/(app)/connect-agent/ConnectionModal.tsx"; do
        substituteInPlace "$f" \
          --replace-fail \
            'process.env.NEXT_PUBLIC_LOCAL_API_URL || "http://localhost:8000"' \
            'process.env.NEXT_PUBLIC_LOCAL_API_URL || "https://kb.scientistexperience.net"'
      done

      # SecurityWidget hardcodes the cloud-only /api/signout href, which is never
      # bundled in a local (NEXT_PUBLIC_IS_CLOUD_ENVIRONMENT=false) build and 404s.
      # The build-time cloud flag covers TopBar's conditional href but not this
      # literal, so rewrite it to the local-mode endpoint that the backend serves.
      substituteInPlace "src/app/(app)/settings/elements/SecurityWidget.tsx" \
        --replace-fail \
          'href="/api/signout"' \
          'href="/api/local-signout"'

      runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export NEXT_TELEMETRY_DISABLED=1
    # Build for local (self-hosted) mode. isCloudEnvironment() defaults to cloud
    # unless this build-time-inlined flag is the literal "false", which flips
    # cloud-gated UI (including TopBar's logout href) to the local endpoints the
    # backend actually serves (/api/local-signout instead of /api/signout).
    export NEXT_PUBLIC_IS_CLOUD_ENVIRONMENT=false
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
