# ============================================================
# Stage: packages - Create yarn install skeleton layer
# ============================================================
FROM registry.access.redhat.com/ubi9/nodejs-24:1 AS packages

USER root
WORKDIR /opt/app-root/src

COPY backstage.json package.json yarn.lock ./
COPY .yarn ./.yarn
COPY .yarnrc.yml ./
COPY packages packages
COPY plugins plugins

RUN find packages \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} \+
RUN find plugins \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} \+

# ============================================================
# Stage: install - Install all dependencies
# ============================================================
FROM registry.access.redhat.com/ubi9/nodejs-24:1 AS install

USER root
ENV PYTHON=/usr/bin/python3

RUN dnf install -y python3 gcc-c++ make sqlite-devel && \
    dnf clean all

WORKDIR /opt/app-root/src

COPY --from=packages --chown=default:root /opt/app-root/src .

RUN npm install -g corepack yarn && \
    corepack enable && \
    yarn install --immutable

# ============================================================
# Stage: dev - Development image with hot reload
# ============================================================
FROM registry.access.redhat.com/ubi9/nodejs-24:1 AS dev

USER root
ENV PYTHON=/usr/bin/python3

RUN dnf install -y python3 gcc-c++ make sqlite-devel && \
    dnf clean all

RUN npm install -g corepack yarn && \
    corepack enable

WORKDIR /opt/app-root/src

COPY --from=install --chown=default:root /opt/app-root/src .
COPY --chown=default:root . .

RUN chgrp -R 0 /opt/app-root/src && \
    chmod -R g+rwX /opt/app-root/src

ENV NODE_OPTIONS="--no-node-snapshot"

ENTRYPOINT []

EXPOSE 3000 7007

CMD ["node", ".yarn/releases/yarn-4.13.0.cjs", "start"]

# ============================================================
# Stage: build - Build the backend for production
# ============================================================
FROM install AS build

COPY --chown=default:root . .

RUN yarn tsc && \
    yarn --cwd packages/backend build && \
    mkdir -p packages/backend/dist/skeleton packages/backend/dist/bundle && \
    tar xzf packages/backend/dist/skeleton.tar.gz -C packages/backend/dist/skeleton && \
    tar xzf packages/backend/dist/bundle.tar.gz -C packages/backend/dist/bundle

# ============================================================
# Stage: production - Minimal production image (OpenShift-ready)
# ============================================================
FROM registry.access.redhat.com/ubi9/nodejs-24-minimal:1 AS production

USER root
WORKDIR /opt/app-root/src

COPY --from=build --chown=default:root /opt/app-root/src/.yarn ./.yarn
COPY --from=build --chown=default:root /opt/app-root/src/.yarnrc.yml ./
COPY --from=build --chown=default:root /opt/app-root/src/backstage.json ./
COPY --from=build --chown=default:root /opt/app-root/src/yarn.lock /opt/app-root/src/package.json /opt/app-root/src/packages/backend/dist/skeleton/ ./

RUN npm install -g corepack yarn && \
    corepack enable && \
    yarn workspaces focus --all --production && \
    rm -rf "$(yarn cache clean)"

COPY --from=build --chown=default:root /opt/app-root/src/packages/backend/dist/bundle/ ./

COPY --chown=default:root app-config*.yaml ./
COPY --chown=default:root examples ./examples

RUN chgrp -R 0 /opt/app-root/src && \
    chmod -R g+rwX /opt/app-root/src

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

USER 1001

ENTRYPOINT []

EXPOSE 7007

CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
