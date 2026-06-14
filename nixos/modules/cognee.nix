{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    optionalString
    boolToString
    getExe'
    ;
  inherit (lib.types)
    bool
    int
    port
    str
    path
    nullOr
    enum
    oneOf
    attrsOf
    listOf
    submodule
    ;

  cfg = config.services.cognee;

  python = cfg.package.pythonModule;
  cogneeEnv = python.withPackages (
    _: [ cfg.package ] ++ lib.optionals usePostgres cfg.package.optional-dependencies.postgres
  );

  mcpPackage = pkgs.python313Packages.cognee-mcp;
  mcpEnv = python.withPackages (_: [ mcpPackage ]);

  effectiveEmbeddingProvider =
    if cfg.llm.embeddingProvider != null then cfg.llm.embeddingProvider else cfg.llm.provider;

  dbProvider = if cfg.database.createLocally then "postgres" else "sqlite";

  hasJwtCredential = cfg.auth.jwtSecretFile != null;
  hasLlmCredential = cfg.llm.apiKeyFile != null;
  hasEmbeddingCredential = cfg.llm.embeddingApiKeyFile != null;
  hasDefaultUserPasswordCredential = cfg.auth.defaultUserPasswordFile != null;

  baseEnv = {
    HTTP_API_HOST = cfg.listenAddress;
    HTTP_API_PORT = toString cfg.port;
    ENV = "prod";
    LOG_LEVEL = "INFO";
    DATA_ROOT_DIRECTORY = "${cfg.dataDir}/data";
    SYSTEM_ROOT_DIRECTORY = "${cfg.dataDir}/system";
    CACHE_ROOT_DIRECTORY = "${cfg.dataDir}/cache";
    COGNEE_LOGS_DIR = "${cfg.dataDir}/logs";
    COGNEE_LOG_FILE = "true";
    HOME = cfg.dataDir;
    DB_PROVIDER = dbProvider;
    DB_NAME = cfg.database.name;
    DB_HOST = cfg.database.host;
    DB_PORT = toString cfg.database.port;
    DB_USERNAME = cfg.database.user;
    VECTOR_DB_PROVIDER = cfg.vectorStore.backend;
    GRAPH_DATABASE_PROVIDER = cfg.graphStore.backend;
    LLM_PROVIDER = cfg.llm.provider;
    LLM_MODEL = cfg.llm.model;
    LLM_ENDPOINT = cfg.llm.endpoint;
    EMBEDDING_PROVIDER = effectiveEmbeddingProvider;
    EMBEDDING_MODEL = cfg.llm.embeddingModel;
    ENABLE_BACKEND_ACCESS_CONTROL = boolToString cfg.auth.multiTenant;
    TELEMETRY_DISABLED = "true";
    TOKENIZERS_PARALLELISM = "false";
  };

  defaultUserEmailEnv = lib.optionalAttrs (cfg.auth.defaultUserEmail != null) {
    DEFAULT_USER_EMAIL = cfg.auth.defaultUserEmail;
  };

  settingsEnv = lib.mapAttrs (
    _: v: if builtins.isList v then lib.concatStringsSep "," v else toString v
  ) cfg.settings;

  cogneeEnvironment = baseEnv // defaultUserEmailEnv // settingsEnv;

  usePostgres = cogneeEnvironment.DB_PROVIDER == "postgres" || cfg.vectorStore.backend == "pgvector";

  hardening = {
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateUsers = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged @setuid @keyring"
      "mbind"
    ];
    UMask = "0077";
    LockPersonality = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
  };

  credentialLoads =
    lib.optional hasJwtCredential "FASTAPI_USERS_JWT_SECRET:${cfg.auth.jwtSecretFile}"
    ++ lib.optional hasLlmCredential "LLM_API_KEY:${cfg.llm.apiKeyFile}"
    ++ lib.optional hasEmbeddingCredential "EMBEDDING_API_KEY:${cfg.llm.embeddingApiKeyFile}"
    ++ lib.optional hasDefaultUserPasswordCredential "DEFAULT_USER_PASSWORD:${cfg.auth.defaultUserPasswordFile}";

  cogneePreStart = ''
    set -eu
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ]; then
      ${optionalString hasJwtCredential ''
        FASTAPI_USERS_JWT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/FASTAPI_USERS_JWT_SECRET")"
        export FASTAPI_USERS_JWT_SECRET
      ''}
      ${optionalString hasLlmCredential ''
        LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/LLM_API_KEY")"
        export LLM_API_KEY
      ''}
      ${optionalString hasEmbeddingCredential ''
        EMBEDDING_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/EMBEDDING_API_KEY")"
        export EMBEDDING_API_KEY
      ''}
    fi
    mkdir -p "${cfg.dataDir}/data" "${cfg.dataDir}/system" \
             "${cfg.dataDir}/cache" "${cfg.dataDir}/logs"
  '';

  cogneeExecStart = ''
    ${cogneeEnv}/bin/gunicorn \
      --workers ${toString cfg.workers} \
      -k uvicorn.workers.UvicornWorker \
      --timeout 30000 \
      --bind ${cfg.listenAddress}:${toString cfg.port} \
      cognee.api.client:app
  '';
in
{
  options.services.cognee = {
    enable = mkEnableOption "Cognee knowledge graph and memory service";

    package = mkOption {
      type = lib.types.package;
      default = pkgs.python313Packages.cognee;
      defaultText = lib.literalExpression "pkgs.python313Packages.cognee";
      description = ''
        The cognee python package, provided via this repository's overlay
        (`python313Packages.cognee`). Override to pin or patch the build.
      '';
    };

    user = mkOption {
      type = str;
      default = "cognee";
      description = "User account under which cognee runs.";
    };

    group = mkOption {
      type = str;
      default = "cognee";
      description = "Group under which cognee runs.";
    };

    dataDir = mkOption {
      type = str;
      default = "/var/lib/cognee";
      description = "Directory where cognee stores runtime state (data, system, cache, logs).";
    };

    listenAddress = mkOption {
      type = str;
      default = "127.0.0.1";
      description = "Address on which the cognee API server listens.";
    };

    port = mkOption {
      type = port;
      default = 8000;
      description = "Port on which the cognee API server listens.";
    };

    workers = mkOption {
      type = int;
      default = 1;
      description = "Number of gunicorn worker processes.";
    };

    openFirewall = mkOption {
      type = bool;
      default = false;
      description = "Whether to open the firewall for the cognee API port.";
    };

    database = {
      createLocally = mkOption {
        type = bool;
        default = true;
        description = "Whether to provision a local PostgreSQL database for cognee.";
      };

      enablePgvector = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to install and enable the pgvector extension on the local
          PostgreSQL database. Required when {option}`services.cognee.vectorStore.backend`
          is set to `pgvector`.
        '';
      };

      host = mkOption {
        type = str;
        default = "/run/postgresql";
        description = "PostgreSQL host or socket directory.";
      };

      port = mkOption {
        type = port;
        default = 5432;
        description = "PostgreSQL port.";
      };

      name = mkOption {
        type = str;
        default = "cognee";
        description = "PostgreSQL database name.";
      };

      user = mkOption {
        type = str;
        default = "cognee";
        description = "PostgreSQL role used by cognee.";
      };
    };

    vectorStore.backend = mkOption {
      type = enum [
        "pgvector"
        "lancedb"
        "qdrant"
      ];
      default = "lancedb";
      description = "Vector store backend.";
    };

    graphStore.backend = mkOption {
      type = enum [
        "ladybug"
        "neo4j"
      ];
      default = "ladybug";
      description = "Graph store backend.";
    };

    llm = {
      provider = mkOption {
        type = enum [
          "openai"
          "anthropic"
          "ollama"
          "azure"
        ];
        default = "openai";
        description = "LLM provider used by cognee.";
      };

      model = mkOption {
        type = str;
        default = "openai/gpt-5-mini";
        description = "LiteLLM-style model identifier.";
      };

      apiKeyFile = mkOption {
        type = nullOr path;
        default = null;
        description = ''
          Path to a file containing the LLM API key. Loaded via
          `LoadCredential` and exported as `LLM_API_KEY` at start. Required
          unless {option}`services.cognee.llm.provider` is `ollama`.
        '';
      };

      endpoint = mkOption {
        type = str;
        default = "";
        description = "Optional LLM endpoint override (e.g. for ollama or azure).";
      };

      embeddingProvider = mkOption {
        type = nullOr (enum [
          "openai"
          "anthropic"
          "ollama"
          "fastembed"
        ]);
        default = null;
        description = ''
          Embedding provider. When `null`, defaults to
          {option}`services.cognee.llm.provider`.
        '';
      };

      embeddingModel = mkOption {
        type = str;
        default = "openai/text-embedding-3-large";
        description = "LiteLLM-style embedding model identifier.";
      };

      embeddingApiKeyFile = mkOption {
        type = nullOr path;
        default = null;
        description = ''
          Path to a file containing the embedding provider API key. When set,
          loaded via `LoadCredential` and exported as `EMBEDDING_API_KEY`.
        '';
      };
    };

    auth = {
      multiTenant = mkOption {
        type = bool;
        default = false;
        description = "Whether to enable multi-tenant backend access control.";
      };

      jwtSecretFile = mkOption {
        type = nullOr path;
        default = null;
        description = ''
          Path to a file containing the FastAPI Users JWT signing secret.
          Required when {option}`services.cognee.enable` is `true`.
        '';
      };

      defaultUserEmail = mkOption {
        type = nullOr str;
        default = null;
        description = "Optional default user email for the bootstrap account.";
      };

      defaultUserPasswordFile = mkOption {
        type = nullOr path;
        default = null;
        description = ''
          Path to a file containing the password for the bootstrapped default
          superuser account. When set, the password is delivered to cognee as
          `DEFAULT_USER_PASSWORD` via a systemd `LoadCredential` (rather than a
          plain environment variable, since it is a secret) and exported at
          start. When `null`, cognee falls back to its built-in default password
          ("default_password") for the bootstrapped superuser, which is insecure
          for any real deployment.
        '';
      };
    };

    settings = mkOption {
      type = submodule {
        freeformType = attrsOf (oneOf [
          bool
          int
          str
          path
          (listOf str)
        ]);
      };
      default = { };
      description = ''
        Free-form environment-variable settings passed to cognee. See the
        upstream `.env.template` at v1.1.2 for the catalog of supported keys.
      '';
    };

    environmentFile = mkOption {
      type = nullOr path;
      default = null;
      description = ''
        Optional `EnvironmentFile=` passed to the cognee service for delivering
        additional secrets or environment-variable overrides.
      '';
    };

    mcp = {
      enable = mkEnableOption "cognee-mcp companion service";

      transport = mkOption {
        type = enum [
          "stdio"
          "sse"
          "http"
        ];
        default = "http";
        description = "MCP transport used by the cognee-mcp companion service.";
      };

      listenAddress = mkOption {
        type = str;
        default = "127.0.0.1";
        description = "Address on which cognee-mcp listens.";
      };

      port = mkOption {
        type = port;
        default = 8765;
        description = "Port on which cognee-mcp listens.";
      };

      proxyApi = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether cognee-mcp should proxy requests to the cognee API service.
          Passes `--api-url http://<cognee-listenAddress>:<cognee-port>` and
          `--no-migration` when enabled.
        '';
      };
    };

    frontend = {
      enable = mkEnableOption "cognee-frontend Next.js UI";

      package = mkOption {
        type = lib.types.package;
        default = pkgs.cognee-frontend or null;
        defaultText = lib.literalExpression "pkgs.cognee-frontend";
        description = ''
          The cognee-frontend package. By default this references
          `pkgs.cognee-frontend`, which is exposed by this repository's
          `packages.<system>.cognee-frontend` flake output rather than via the
          shared overlay (it is not a python package).
        '';
      };

      listenAddress = mkOption {
        type = str;
        default = "127.0.0.1";
        description = "Hostname on which the frontend listens.";
      };

      port = mkOption {
        type = port;
        default = 3000;
        description = "Port on which the frontend listens.";
      };

      backendApiUrl = mkOption {
        type = str;
        default = "http://localhost:8000/api";
        description = "Backend API URL injected into the frontend (`NEXT_PUBLIC_BACKEND_API_URL`).";
      };
    };

    nginx = {
      enable = mkEnableOption "nginx reverse proxy for cognee";

      domain = mkOption {
        type = nullOr str;
        default = null;
        description = "Public domain served by the nginx virtual host.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.auth.jwtSecretFile != null;
          message = "services.cognee.auth.jwtSecretFile must be set when services.cognee.enable = true. Use a clan-vars or sops-nix secret containing the FASTAPI_USERS_JWT_SECRET value.";
        }
        {
          assertion = cfg.llm.apiKeyFile != null || cfg.llm.provider == "ollama";
          message = "services.cognee.llm.apiKeyFile must be set unless using ollama (which uses LLM_ENDPOINT).";
        }
        {
          assertion = !(cfg.vectorStore.backend == "pgvector" && !cfg.database.enablePgvector);
          message = "services.cognee.database.enablePgvector must be true when vectorStore.backend = pgvector.";
        }
      ];

      users.users = mkIf (cfg.user == "cognee") {
        cognee = {
          isSystemUser = true;
          inherit (cfg) group;
          home = cfg.dataDir;
        };
      };

      users.groups = mkIf (cfg.group == "cognee") {
        cognee = { };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [ cfg.port ];
      };

      systemd.services.cognee = {
        description = "Cognee knowledge graph and memory service";
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.database.createLocally "postgresql.target";
        requires = lib.optional cfg.database.createLocally "postgresql.target";
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = cogneeEnvironment;

        serviceConfig = hardening // {
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "cognee";
          StateDirectoryMode = "0700";
          WorkingDirectory = cfg.dataDir;
          ReadWritePaths = [ cfg.dataDir ];
          LoadCredential = credentialLoads;
          EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
          ExecStartPre = pkgs.writeShellScript "cognee-pre-start" cogneePreStart;
          ExecStart = pkgs.writeShellScript "cognee-start" ''
            set -eu
            if [ -n "''${CREDENTIALS_DIRECTORY:-}" ]; then
              ${optionalString hasJwtCredential ''
                FASTAPI_USERS_JWT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/FASTAPI_USERS_JWT_SECRET")"
                export FASTAPI_USERS_JWT_SECRET
              ''}
              ${optionalString hasLlmCredential ''
                LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/LLM_API_KEY")"
                export LLM_API_KEY
              ''}
              ${optionalString hasEmbeddingCredential ''
                EMBEDDING_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/EMBEDDING_API_KEY")"
                export EMBEDDING_API_KEY
              ''}
              ${optionalString hasDefaultUserPasswordCredential ''
                DEFAULT_USER_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/DEFAULT_USER_PASSWORD")"
                export DEFAULT_USER_PASSWORD
              ''}
            fi
            exec ${cogneeExecStart}
          '';
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    }

    (mkIf cfg.database.createLocally {
      services.postgresql = {
        enable = true;
        ensureDatabases = [ cfg.database.name ];
        ensureUsers = [
          {
            name = cfg.database.user;
            ensureDBOwnership = true;
          }
        ];
        extensions = mkIf cfg.database.enablePgvector (ps: [ ps.pgvector ]);
      };

      systemd.services.postgresql-setup.serviceConfig.ExecStartPost = mkIf cfg.database.enablePgvector [
        "${getExe' config.services.postgresql.package "psql"} -d ${cfg.database.name} -c 'CREATE EXTENSION IF NOT EXISTS vector;'"
      ];
    })

    (mkIf cfg.mcp.enable {
      systemd.services.cognee-mcp = {
        description = "Cognee MCP companion service";
        after = [
          "network-online.target"
          "cognee.service"
        ];
        requires = lib.optional cfg.mcp.proxyApi "cognee.service";
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = cfg.dataDir;
          TELEMETRY_DISABLED = "true";
          TOKENIZERS_PARALLELISM = "false";
        };

        serviceConfig = hardening // {
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "cognee";
          StateDirectoryMode = "0700";
          WorkingDirectory = cfg.dataDir;
          ReadWritePaths = [ cfg.dataDir ];
          ExecStart = ''
            ${mcpEnv}/bin/cognee-mcp --transport ${cfg.mcp.transport} --host ${cfg.mcp.listenAddress} --port ${toString cfg.mcp.port}${optionalString cfg.mcp.proxyApi " --api-url http://${cfg.listenAddress}:${toString cfg.port}"}${optionalString cfg.mcp.proxyApi " --no-migration"}
          '';
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    })

    (mkIf cfg.frontend.enable {
      systemd.services.cognee-frontend = {
        description = "Cognee frontend (Next.js)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          NODE_ENV = "production";
          PORT = toString cfg.frontend.port;
          HOSTNAME = cfg.frontend.listenAddress;
          NEXT_PUBLIC_BACKEND_API_URL = cfg.frontend.backendApiUrl;
        };

        serviceConfig = hardening // {
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "cognee";
          StateDirectoryMode = "0700";
          WorkingDirectory = "${cfg.frontend.package}/share/cognee-frontend";
          ReadWritePaths = [ cfg.dataDir ];
          ExecStart = "${cfg.frontend.package}/bin/cognee-frontend -p ${toString cfg.frontend.port} -H ${cfg.frontend.listenAddress}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    })

    (mkIf cfg.nginx.enable {
      assertions = [
        {
          assertion = cfg.nginx.domain != null;
          message = "services.cognee.nginx.domain must be set when services.cognee.nginx.enable = true.";
        }
      ];

      services.nginx = {
        enable = true;
        virtualHosts.${toString cfg.nginx.domain} = {
          forceSSL = true;
          enableACME = true;
          locations."/api/" = {
            proxyPass = "http://${cfg.listenAddress}:${toString cfg.port}/api/";
          };
          locations."/" = mkIf cfg.frontend.enable {
            proxyPass = "http://${cfg.frontend.listenAddress}:${toString cfg.frontend.port}/";
          };
        };
      };
    })
  ]);

  meta = {
    maintainers = [ ];
    doc = ./cognee.md;
  };
}
