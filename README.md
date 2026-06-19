# [Backstage](https://backstage.io)

This is your newly scaffolded Backstage App, Good Luck!

## Table of Contents

- [Local Development](#local-development)
- [Docker](#docker)
  - [Development Mode](#development-mode)
  - [Production Mode](#production-mode)
  - [Database](#database)
  - [Environment Variables](#environment-variables)
- [Plugin Development Guide](#plugin-development-guide)
  - [1. Creating a Frontend Plugin](#1-creating-a-frontend-plugin)
  - [2. Creating a Backend Plugin](#2-creating-a-backend-plugin)
  - [3. Creating a Full-Stack Plugin (Front + Back)](#3-creating-a-full-stack-plugin-front--back)
  - [4. Shared Code Between Frontend and Backend](#4-shared-code-between-frontend-and-backend)
  - [5. Frontend Plugin Architecture Best Practices](#5-frontend-plugin-architecture-best-practices)
  - [6. Backend Plugin Architecture Best Practices](#6-backend-plugin-architecture-best-practices)
  - [7. Avoiding Library Version Conflicts](#7-avoiding-library-version-conflicts)
  - [8. Integrating Community Plugins Safely](#8-integrating-community-plugins-safely)
  - [9. Creating and Deploying a Backstage Operator](#9-creating-and-deploying-a-backstage-operator)
  - [10. OpenShift Deployment](#10-openshift-deployment)

## Local Development

To start the app locally, run:

```sh
yarn install
yarn start
```

## Docker

The project includes a multi-stage Dockerfile based on Red Hat UBI9 Node.js 24 images, designed to be compatible with OpenShift deployments.

### Development Mode

Runs Backstage with hot reload and source code mounting:

```sh
docker compose --profile dev up
```

- Frontend: http://localhost:3000
- Backend: http://localhost:7007
- Source code is mounted as a volume for live editing

### Production Mode

Builds and runs the optimized production image:

```sh
docker compose --profile prod up
```

- Backend: http://localhost:7007
- Frontend is served by the backend

### Database

Both modes use PostgreSQL 16. Data persists in the `postgres_data` volume.

### Environment Variables

The following environment variables are pre-configured in docker-compose.yml:

- `POSTGRES_HOST`: postgres
- `POSTGRES_PORT`: 5432
- `POSTGRES_USER`: backstage
- `POSTGRES_PASSWORD`: backstage

---

## Plugin Development Guide

### 1. Creating a Frontend Plugin

Run the scaffolding command from the repo root:

```sh
yarn new
# Select "plugin" and enter a plugin ID (e.g. "my-dashboard")
```

This creates `plugins/my-dashboard/` with the standard structure:

```
plugins/my-dashboard/
  dev/
    index.ts            # Dev server entry point
  src/
    components/
      MyDashboardPage/
        MyDashboardPage.tsx
        index.ts
    plugin.ts           # Plugin definition
    routes.ts           # Route references
    index.ts            # Package exports
  package.json
```

**Plugin definition** (`src/plugin.ts`):

```ts
import {
  createFrontendPlugin,
  PageBlueprint,
} from '@backstage/frontend-plugin-api';
import { RiDashboardLine } from '@remixicon/react';
import { rootRouteRef } from './routes';

const myDashboardPage = PageBlueprint.make({
  params: {
    routeRef: rootRouteRef,
    path: '/my-dashboard',
    title: 'My Dashboard',
    icon: <RiDashboardLine />,
    loader: () =>
      import('./components/MyDashboardPage').then(m => (
        <m.MyDashboardPage />
      )),
  },
});

export const myDashboardPlugin = createFrontendPlugin({
  pluginId: 'my-dashboard',
  extensions: [myDashboardPage],
  routes: {
    root: rootRouteRef,
  },
});

export default myDashboardPlugin;
```

**Route reference** (`src/routes.ts`):

```ts
import { createRouteRef } from '@backstage/frontend-plugin-api';

export const rootRouteRef = createRouteRef();
```

**Register in the app** — add the plugin as a dependency in `packages/app/package.json`:

```json
{
  "dependencies": {
    "@internal/plugin-my-dashboard": "workspace:*"
  }
}
```

The new frontend system auto-discovers plugins added as dependencies. No manual import needed.

**Run the plugin in isolation** during development:

```sh
yarn workspace @internal/plugin-my-dashboard start
```

---

### 2. Creating a Backend Plugin

```sh
yarn new
# Select "backend-plugin" and enter a plugin ID (e.g. "my-service")
```

This creates `plugins/my-service-backend/`:

```
plugins/my-service-backend/
  src/
    service/
      router.ts         # Express router
    plugin.ts           # Plugin definition
    index.ts            # Package exports
  package.json
```

**Plugin definition** (`src/plugin.ts`):

```ts
import {
  createBackendPlugin,
  coreServices,
} from '@backstage/backend-plugin-api';
import { createRouter } from './service/router';

export const myServicePlugin = createBackendPlugin({
  pluginId: 'my-service',
  register(env) {
    env.registerInit({
      deps: {
        logger: coreServices.logger,
        httpRouter: coreServices.httpRouter,
        database: coreServices.database,
        httpAuth: coreServices.httpAuth,
      },
      async init({ logger, httpRouter, database, httpAuth }) {
        logger.info('Initializing my-service plugin');
        const router = await createRouter({ logger, database, httpAuth });
        httpRouter.use(router);
        httpRouter.addAuthPolicy({
          path: '/health',
          allow: 'unauthenticated',
        });
      },
    });
  },
});

export default myServicePlugin;
```

**Router** (`src/service/router.ts`):

```ts
import { LoggerService } from '@backstage/backend-plugin-api';
import express from 'express';

export interface RouterOptions {
  logger: LoggerService;
  database: any;
  httpAuth: any;
}

export async function createRouter(
  options: RouterOptions,
): Promise<express.Router> {
  const { logger } = options;
  const router = express.Router();

  router.get('/health', (_, res) => {
    res.json({ status: 'ok' });
  });

  router.get('/items', async (req, res) => {
    logger.info('Fetching items');
    res.json({ items: [] });
  });

  return router;
}
```

**Register in the backend** — add to `packages/backend/src/index.ts`:

```ts
const backend = createBackend();

// ... existing plugins ...

backend.add(import('@internal/plugin-my-service-backend'));

backend.start();
```

Also add the dependency in `packages/backend/package.json`:

```json
{
  "dependencies": {
    "@internal/plugin-my-service-backend": "workspace:*"
  }
}
```

---

### 3. Creating a Full-Stack Plugin (Front + Back)

A full-stack plugin typically consists of **3 packages**:

```
plugins/
  my-feature/                  # Frontend plugin
  my-feature-backend/          # Backend plugin
  my-feature-common/           # Shared types and API contracts
```

**Step 1: Create the common package**

```sh
yarn new
# Select "common-plugin" and enter "my-feature"
```

This creates `plugins/my-feature-common/` with shared types:

```ts
// plugins/my-feature-common/src/types.ts
export interface FeatureItem {
  id: string;
  name: string;
  status: 'active' | 'inactive';
}
```

```ts
// plugins/my-feature-common/src/index.ts
export * from './types';
```

**Step 2: Create the backend plugin** (as shown in section 2)

The backend depends on the common package:

```json
{
  "dependencies": {
    "@internal/plugin-my-feature-common": "workspace:*"
  }
}
```

**Step 3: Create the frontend plugin** (as shown in section 1)

The frontend uses a Utility API to call the backend:

```ts
// plugins/my-feature/src/api.ts
import { createApiRef } from '@backstage/frontend-plugin-api';
import { FeatureItem } from '@internal/plugin-my-feature-common';

export interface MyFeatureApi {
  getItems(): Promise<FeatureItem[]>;
}

export const myFeatureApiRef = createApiRef<MyFeatureApi>({
  id: 'plugin.my-feature.api',
});
```

```ts
// plugins/my-feature/src/api/MyFeatureClient.ts
import { DiscoveryApi, FetchApi } from '@backstage/frontend-plugin-api';
import { MyFeatureApi } from '../api';
import { FeatureItem } from '@internal/plugin-my-feature-common';

export class MyFeatureClient implements MyFeatureApi {
  private readonly discoveryApi: DiscoveryApi;
  private readonly fetchApi: FetchApi;

  constructor(options: { discoveryApi: DiscoveryApi; fetchApi: FetchApi }) {
    this.discoveryApi = options.discoveryApi;
    this.fetchApi = options.fetchApi;
  }

  async getItems(): Promise<FeatureItem[]> {
    const baseUrl = await this.discoveryApi.getBaseUrl('my-feature');
    const response = await this.fetchApi.fetch(`${baseUrl}/items`);
    if (!response.ok) throw new Error(`Failed to fetch: ${response.statusText}`);
    return response.json();
  }
}
```

---

### 4. Shared Code Between Frontend and Backend

Create a dedicated workspace package for shared utilities:

```sh
mkdir -p packages/shared/src
```

**`packages/shared/package.json`**:

```json
{
  "name": "@internal/shared",
  "version": "0.0.0",
  "private": true,
  "main": "src/index.ts",
  "types": "src/index.ts",
  "dependencies": {}
}
```

**`packages/shared/src/index.ts`**:

```ts
export * from './constants';
export * from './validators';
export * from './types';
```

**Consume from any workspace** — add the dependency:

```json
{
  "dependencies": {
    "@internal/shared": "workspace:*"
  }
}
```

Then import:

```ts
import { validateEmail, APP_NAME } from '@internal/shared';
```

**What belongs in shared packages:**

| Good for shared | Not for shared |
|---|---|
| TypeScript types and interfaces | React components |
| Validation schemas (zod, yup) | Backend-specific logic (DB, auth) |
| Constants and enums | UI-specific hooks |
| Pure utility functions | Anything with side effects |
| API contracts (request/response shapes) | Framework-specific code |

---

### 5. Frontend Plugin Architecture Best Practices

**Recommended folder structure:**

```
plugins/my-plugin/
  dev/
    index.ts
  src/
    api/
      MyPluginApi.ts          # API interface
      MyPluginClient.ts       # API implementation
      index.ts
    components/
      MyPluginPage/
        MyPluginPage.tsx
        MyPluginPage.test.tsx
        index.ts
      MyPluginCard/
        MyPluginCard.tsx
        index.ts
    hooks/
      useMyPluginData.ts
    plugin.ts
    routes.ts
    index.ts
  package.json
```

**Key principles:**

- **Use Blueprints** for all extensions. The new frontend system provides `PageBlueprint`, `EntityContentBlueprint`, `NavBlueprint`, `ApiBlueprint`, and more. Avoid raw `createComponentExtension`.

- **Lazy load everything.** Page and entity content components should always use dynamic `import()`:

  ```ts
  loader: () => import('./components/MyPage').then(m => <m.MyPage />)
  ```

- **Encapsulate API calls in Utility APIs.** Never call `fetch` directly from components. Use `ApiBlueprint` to register an API client, then consume it via `useApi()`.

- **Use `ExternalRouteRef` for cross-plugin links.** Never import route refs from other plugins directly. Declare an external route ref and let the app bind it:

  ```ts
  const catalogRouteRef = createExternalRouteRef({ id: 'catalog' });
  ```

- **Keep `plugin.ts` as the single wiring point.** All extensions, routes, and feature flags are declared here. Components and APIs are internal implementation details.

- **Use `plugin.withOverrides()` for customization** instead of forking:

  ```ts
  import plugin from '@backstage/plugin-catalog';

  export default plugin.withOverrides({
    extensions: [
      plugin.getExtension('page:catalog').override({
        factory: origFactory =>
          origFactory({
            loader: () => import('./CustomCatalogPage').then(m => <m.Page />),
          }),
      }),
    ],
  });
  ```

---

### 6. Backend Plugin Architecture Best Practices

**Recommended folder structure:**

```
plugins/my-plugin-backend/
  src/
    service/
      router.ts               # Express router (HTTP layer)
      MyService.ts            # Business logic
    database/
      DatabaseHandler.ts      # Database access
      migrations/
        20240101_init.ts
    plugin.ts                 # Plugin definition
    index.ts                  # Package exports
  package.json
```

**Key principles:**

- **Use `coreServices` for dependency injection.** Never import singletons or create instances manually. Declare dependencies in `deps` and receive them in `init`:

  ```ts
  deps: {
    logger: coreServices.logger,
    httpRouter: coreServices.httpRouter,
    database: coreServices.database,
    config: coreServices.rootConfig,
    httpAuth: coreServices.httpAuth,
    userInfo: coreServices.userInfo,
  }
  ```

- **Separate concerns into layers:**
  - **Router** (`router.ts`): HTTP request/response handling, input validation
  - **Service** (`MyService.ts`): Business logic, orchestration
  - **Database** (`DatabaseHandler.ts`): Queries, migrations, data access

- **Use Knex for database migrations** with prefixed table names to avoid collisions:

  ```ts
  const knex = await database.getClient();
  await knex.migrate.latest({
    directory: migrationsDir,
    tableName: 'my_plugin__knex_migrations',
  });
  ```

- **Expose extension points** when your plugin should be extensible by modules:

  ```ts
  export const myExtensionPoint = createExtensionPoint<MyExtension>({
    id: 'my-plugin.my-extension',
  });
  ```

- **Use `httpAuth` for authentication.** Always extract credentials from requests:

  ```ts
  router.get('/items', async (req, res) => {
    const credentials = await httpAuth.credentials(req);
    // Use credentials for authorization
  });
  ```

- **Prefix module HTTP routes** under `/modules/<module-id>/` to avoid conflicts with the main plugin routes.

---

### 7. Avoiding Library Version Conflicts

When two plugins need different versions of the same library, use these strategies in order of preference:

**a. Yarn `resolutions` (root `package.json`)**

Force a single version across the entire monorepo:

```json
{
  "resolutions": {
    "lodash": "4.17.21",
    "axios": "1.7.0"
  }
}
```

**b. Scoped resolutions**

Target a specific dependency tree without affecting others:

```json
{
  "resolutions": {
    "plugin-a/lodash": "4.17.21",
    "plugin-b/lodash": "3.10.1"
  }
}
```

This lets `plugin-a` use lodash v4 while `plugin-b` uses lodash v3.

**c. `peerDependencies` in shared packages**

Let the consumer provide the version:

```json
{
  "name": "@internal/shared-utils",
  "peerDependencies": {
    "react": "^18.0.0",
    "@backstage/core-plugin-api": "^1.0.0"
  }
}
```

**d. `peerDependenciesMeta` for optional peers**

Silence warnings for optional peer dependencies:

```json
{
  "peerDependencies": {
    "react": "^18.0.0",
    "graphql": "^16.0.0"
  },
  "peerDependenciesMeta": {
    "graphql": {
      "optional": true
    }
  }
}
```

**e. `installConfig.hoistingLimits`**

Prevent hoisting conflicts between workspaces:

```json
{
  "name": "plugin-with-conflict",
  "installConfig": {
    "hoistingLimits": "workspaces"
  }
}
```

This keeps the plugin's dependencies isolated and prevents them from being hoisted to the root `node_modules`.

**f. General guidelines**

- Prefer aligning on a single version across the monorepo whenever possible
- Use `yarn why <package>` to investigate why a specific version is installed
- Use `yarn explain peer-requirements` to diagnose peer dependency issues
- Avoid `resolutions` for `@backstage/*` packages — they are tested together and pinning can cause subtle bugs

---

### 8. Integrating Community Plugins Safely

**Before installing:**

1. Check the [Backstage Plugin Directory](https://backstage.io/plugins) for maintained plugins
2. Verify the plugin's `peerDependencies` match your Backstage version
3. Check the plugin's last release date and open issues

**Installation:**

```sh
# Frontend plugin
yarn workspace app add @backstage-community/plugin-<name>

# Backend plugin
yarn workspace backend add @backstage-community/plugin-<name>-backend
```

**Pin versions explicitly** rather than using `^` ranges:

```json
{
  "dependencies": {
    "@backstage-community/plugin-foo": "1.2.3"
  }
}
```

**Test in isolation first** using `createDevApp`:

```ts
// dev/index.ts
import { createDevApp } from '@backstage/frontend-dev-utils';
import fooPlugin from '@backstage-community/plugin-foo';

createDevApp({ features: [fooPlugin] });
```

**Resolve transitive dependency conflicts** with scoped resolutions:

```json
{
  "resolutions": {
    "@backstage-community/plugin-foo/lodash": "4.17.21"
  }
}
```

**Customize without forking** using `plugin.withOverrides()`:

```ts
import plugin from '@backstage-community/plugin-foo';

export default plugin.withOverrides({
  extensions: [
    plugin.getExtension('page:foo').override({
      factory: origFactory =>
        origFactory({
          loader: () => import('./CustomFooPage').then(m => <m.Page />),
        }),
    }),
  ],
});
```

**When upgrading Backstage:**

- Check the [changelog](https://backstage.io/docs/releases) for breaking changes
- Verify community plugins have released compatible versions before upgrading
- Run `yarn dedupe` after upgrades to clean up duplicate transitive dependencies
- Use `yarn why @backstage/core-plugin-api` to check for version mismatches

---

### 9. Creating and Deploying a Backstage Operator

A Backstage Operator manages the lifecycle of your Backstage instance on Kubernetes/OpenShift using the Operator pattern. It automates deployment, scaling, upgrades, and configuration.

**When to use an operator:**

- You need to manage multiple Backstage instances across clusters
- You want automated upgrades and lifecycle management
- You need custom reconciliation logic (e.g., auto-provision databases)
- You want to expose Backstage configuration as Kubernetes CRDs

#### Create the Operator

Use the [Operator SDK](https://sdk.operatorframework.io/) to scaffold the operator:

```sh
# Install operator-sdk
brew install operator-sdk  # macOS
# or download from https://sdk.operatorframework.io/docs/installation/

# Create operator project
mkdir backstage-operator && cd backstage-operator
operator-sdk init --domain=example.com --repo=github.com/your-org/backstage-operator

# Create API for Backstage custom resource
operator-sdk create api --group=backstage --version=v1alpha1 --kind=Backstage --resource --controller
```

#### Define the CRD

Edit `api/v1alpha1/backstage_types.go`:

```go
type BackstageSpec struct {
  // Image is the Backstage container image
  Image string `json:"image,omitempty"`
  // Replicas is the number of Backstage instances
  Replicas *int32 `json:"replicas,omitempty"`
  // Database configuration
  Database DatabaseSpec `json:"database,omitempty"`
}

type DatabaseSpec struct {
  // Host is the PostgreSQL host
  Host string `json:"host,omitempty"`
  // Port is the PostgreSQL port
  Port int32 `json:"port,omitempty"`
  // CredentialsSecret references a Secret with database credentials
  CredentialsSecret string `json:"credentialsSecret,omitempty"`
}

type BackstageStatus struct {
  // Conditions represent the latest available observations
  Conditions []metav1.Condition `json:"conditions,omitempty"`
  // Ready indicates if the Backstage instance is ready
  Ready bool `json:"ready,omitempty"`
}
```

#### Implement the Controller

Edit `internal/controller/backstage_controller.go`:

```go
func (r *BackstageReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
  // Fetch the Backstage instance
  backstage := &backstagev1alpha1.Backstage{}
  err := r.Get(ctx, req.NamespacedName, backstage)
  if err != nil {
    return ctrl.Result{}, client.IgnoreNotFound(err)
  }

  // Reconcile the Deployment
  deployment := r.deploymentForBackstage(backstage)
  if err := r.reconcileDeployment(ctx, deployment); err != nil {
    return ctrl.Result{}, err
  }

  // Reconcile the Service
  service := r.serviceForBackstage(backstage)
  if err := r.reconcileService(ctx, service); err != nil {
    return ctrl.Result{}, err
  }

  // Update status
  backstage.Status.Ready = true
  if err := r.Status().Update(ctx, backstage); err != nil {
    return ctrl.Result{}, err
  }

  return ctrl.Result{}, nil
}

func (r *BackstageReconciler) deploymentForBackstage(bs *backstagev1alpha1.Backstage) *appsv1.Deployment {
  replicas := int32(1)
  if bs.Spec.Replicas != nil {
    replicas = *bs.Spec.Replicas
  }

  return &appsv1.Deployment{
    ObjectMeta: metav1.ObjectMeta{
      Name:      bs.Name,
      Namespace: bs.Namespace,
    },
    Spec: appsv1.DeploymentSpec{
      Replicas: &replicas,
      Selector: &metav1.LabelSelector{
        MatchLabels: map[string]string{"app": bs.Name},
      },
      Template: corev1.PodTemplateSpec{
        ObjectMeta: metav1.ObjectMeta{
          Labels: map[string]string{"app": bs.Name},
        },
        Spec: corev1.PodSpec{
          Containers: []corev1.Container{{
            Name:  "backstage",
            Image: bs.Spec.Image,
            Ports: []corev1.ContainerPort{{ContainerPort: 7007}},
            Env: []corev1.EnvVar{
              {Name: "POSTGRES_HOST", Value: bs.Spec.Database.Host},
              {Name: "POSTGRES_PORT", Value: strconv.Itoa(int(bs.Spec.Database.Port))},
            },
          }},
        },
      },
    },
  }
}
```

#### Build and Deploy the Operator

```sh
# Build the operator image
make docker-build IMG=<registry>/<namespace>/backstage-operator:v0.1.0

# Push to registry
make docker-push IMG=<registry>/<namespace>/backstage-operator:v0.1.0

# Deploy to cluster
make deploy IMG=<registry>/<namespace>/backstage-operator:v0.1.0
```

#### Create a Backstage Instance

Create a custom resource:

```yaml
apiVersion: backstage.example.com/v1alpha1
kind: Backstage
metadata:
  name: my-backstage
spec:
  image: <registry>/<namespace>/backstage:latest
  replicas: 2
  database:
    host: backstage-postgres
    port: 5432
    credentialsSecret: backstage-db-secret
```

Apply it:

```sh
oc apply -f backstage-cr.yaml
```

The operator will automatically create and manage the Deployment, Service, and any other resources needed for your Backstage instance.

#### OpenShift-Specific Notes

- Use `operator-sdk` with `--type=ansible` or `--type=helm` if you prefer declarative reconciliation
- For OpenShift, add RBAC rules for Route resources if your operator manages Routes
- Use the [OpenShift Operator Lifecycle Manager (OLM)](https://olm.operatorframework.io/) to distribute your operator
- Package the operator as a [ClusterServiceVersion (CSV)](https://olm.operatorframework.io/docs/concepts/crds/clusterserviceversion/) for OLM installation

---

### 10. OpenShift Deployment

The production image is built on Red Hat UBI9 and is OpenShift-compatible out of the box (runs as non-root, group 0 permissions, no hardcoded UIDs).

#### 1. Build and Push the Image

```sh
# Build the production image
docker build --target production -t <registry>/<namespace>/backstage:latest .

# Push to your container registry
docker push <registry>/<namespace>/backstage:latest
```

#### 2. Database

Use the [Crunchy Data PostgreSQL Operator](https://access.crunchydata.com/documentation/postgres-operator/) or a managed PostgreSQL service. Create a `PostgresCluster` or use an existing instance.

Alternatively, for a simple setup, deploy PostgreSQL directly:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backstage-postgres
  template:
    metadata:
      labels:
        app: backstage-postgres
    spec:
      containers:
        - name: postgres
          image: registry.access.redhat.com/ubi9/postgresql-16:latest
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRESQL_USER
              valueFrom:
                secretKeyRef:
                  name: backstage-db-secret
                  key: username
            - name: POSTGRESQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backstage-db-secret
                  key: password
            - name: POSTGRESQL_DATABASE
              value: backstage
          volumeMounts:
            - name: data
              mountPath: /var/lib/pgsql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: backstage-postgres-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backstage-postgres-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

#### 3. Secrets and ConfigMaps

**Database credentials:**

```sh
oc create secret generic backstage-db-secret \
  --from-literal=username=backstage \
  --from-literal=password=<your-password>
```

**Backstage config** — store `app-config.production.yaml` as a ConfigMap:

```sh
oc create configmap backstage-config \
  --from-file=app-config.production.yaml=./app-config.production.yaml
```

#### 4. Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backstage
  template:
    metadata:
      labels:
        app: backstage
    spec:
      containers:
        - name: backstage
          image: <registry>/<namespace>/backstage:latest
          ports:
            - containerPort: 7007
              name: http
          env:
            - name: POSTGRES_HOST
              value: backstage-postgres
            - name: POSTGRES_PORT
              value: "5432"
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: backstage-db-secret
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backstage-db-secret
                  key: password
          volumeMounts:
            - name: config
              mountPath: /opt/app-root/src/app-config.production.yaml
              subPath: app-config.production.yaml
          readinessProbe:
            httpGet:
              path: /healthcheck
              port: 7007
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthcheck
              port: 7007
            initialDelaySeconds: 60
            periodSeconds: 30
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
      volumes:
        - name: config
          configMap:
            name: backstage-config
```

#### 5. Service and Route

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backstage
spec:
  selector:
    app: backstage
  ports:
    - port: 7007
      targetPort: 7007
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: backstage
spec:
  to:
    kind: Service
    name: backstage
  port:
    targetPort: 7007
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

#### 6. Apply

```sh
oc apply -f deployment.yaml
oc apply -f service.yaml
oc apply -f route.yaml
```

#### OpenShift-Specific Notes

- **No `securityContext` needed** — the UBI9 image runs as UID 1001 with group 0, which OpenShift's anyuid/restricted SCCs handle automatically
- **`ENTRYPOINT []`** is set in the Dockerfile to override UBI9's default container-entrypoint
- **`NODE_OPTIONS="--no-node-snapshot"`** is required for the scaffolder plugin to work
- **Health endpoint** — add a `/healthcheck` route to your backend plugin or use the built-in `app-backend` health check at `/`
- **Image registry** — use OpenShift's internal registry (`image-registry.openshift-image-registry.svc:5000`) or push to an external registry and create an `ImageStream`
