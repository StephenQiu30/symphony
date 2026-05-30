FROM elixir:1.19.5-otp-28

ARG CODEX_VERSION=0.135.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    nodejs \
    npm \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@openai/codex@${CODEX_VERSION}"

WORKDIR /app/elixir

COPY elixir/mix.exs elixir/mix.lock ./
COPY elixir/config ./config

RUN mix local.hex --force \
  && mix local.rebar --force \
  && mix deps.get

COPY elixir ./

RUN mix build

EXPOSE 4000

ENTRYPOINT ["./bin/symphony", "--i-understand-that-this-will-be-running-without-the-usual-guardrails"]
CMD ["--port", "4000", "./WORKFLOW.md"]
