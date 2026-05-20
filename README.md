# Tienda de Ropa — Vintage & Streetwear

Aplicación web de e-commerce para una tienda de ropa vintage y streetwear. Permite a los usuarios registrarse, autenticarse, consultar el catálogo de artículos y realizar compras.

---

## Arquitectura

![Arquitectura](arquitectura.png)

El sistema se compone de tres capas:

- **Frontend** — Aplicación React + Vite servida por Nginx. Se comunica con la API para obtener el catálogo y gestionar las sesiones de usuario.
- **API (Backend)** — Servidor FastAPI (Python) que expone los endpoints REST, gestiona la autenticación JWT y sirve las imágenes de producto.
- **Base de datos** — PostgreSQL 15 con el esquema de usuarios, artículos y transacciones.

---

## Base de datos

![Base de datos](bbdd.png)

Tres tablas principales:

| Tabla | Descripción |
|-------|-------------|
| `usuarios` | Cuentas de usuario con email único y contraseña hasheada |
| `articulos` | Catálogo de productos con precio, talla, categoría e imagen |
| `transacciones` | Historial de compras vinculando usuarios y artículos |

---

## Servidor / API

![Servidor](servidor.png)

La API está construida con **FastAPI** y expone los siguientes endpoints:

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/ping-pong` | Health check |
| `POST` | `/register` | Registro de usuario (devuelve JWT) |
| `POST` | `/login` | Login (devuelve JWT) |
| `GET` | `/me` | Perfil del usuario autenticado |
| `GET` | `/getArticulos` | Listado de artículos (filtros: talla, estado) |
| `GET` | `/getDrops` | Artículos marcados como drop |
| `GET` | `/getDestacado` | Artículo destacado |
| `GET` | `/getCompraUserId` | Historial de compras del usuario autenticado |
| `POST` | `/setCompraUserId` | Registrar una compra |
| `GET` | `/images/{filename}` | Imágenes de producto servidas como estáticos |

---

## Estructura del proyecto

```
├── frontend/          # Aplicación React + Vite
├── server/            # API FastAPI (Python)
├── init-db/           # Scripts SQL de inicialización de la base de datos
├── images/            # Imágenes de producto
├── GCP/               # Infraestructura como código (Terraform) y script de despliegue
│   ├── deploy.sh
│   ├── envs/dev/terraform/
│   │   ├── 00_base/   # Artifact Registry + Service Account
│   │   ├── 01_data/   # Cloud SQL + Secret Manager
│   │   └── 02_app/    # Cloud Run (API + Frontend)
│   └── modules/       # Módulos Terraform reutilizables
├── docker-compose.yml # Entorno de desarrollo local
└── .env.example       # Variables de entorno de ejemplo
```

---

## Desarrollo local

### Requisitos

- Docker Desktop

### Pasos

1. Copia el fichero de variables de entorno y edita los valores:

```bash
cp .env.example .env
```

2. Levanta todos los servicios:

```bash
docker-compose up --build
```

| Servicio | URL |
|----------|-----|
| Frontend | http://localhost:3000 |
| API | http://localhost:8000 |
| Docs API (Swagger) | http://localhost:8000/docs |

---

## Despliegue en GCP

### Requisitos previos

- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) instalado
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 instalado
- Docker Desktop en ejecución
- Un proyecto GCP con facturación habilitada
- El bucket de Terraform State creado en GCP (una sola vez):

```bash
gsutil mb gs://bucker_exa
```

---

### 1. Configurar el perfil de gcloud

El script `deploy.sh` **lee automáticamente** el proyecto y la región del perfil activo de `gcloud`. No hay que editar ningún fichero — basta con tener el perfil correctamente configurado antes de lanzar el deploy.

#### Crear un perfil (configuración) de gcloud

```bash
gcloud config configurations create <nombre-perfil>
```

> Ejemplo: `gcloud config configurations create data-project-3`

#### Autenticarse con tu cuenta de Google

```bash
gcloud auth login
```

Se abrirá el navegador para completar la autenticación.

#### Establecer el proyecto de GCP

```bash
gcloud config set project <PROJECT_ID>
```

> Ejemplo: `gcloud config set project my-project-123456`

#### Establecer la región

```bash
gcloud config set compute/region <REGION>
```

> Ejemplo: `gcloud config set compute/region europe-west1`

#### Verificar la configuración activa

```bash
gcloud config list
```

Deberías ver `project` y `compute/region` con los valores correctos.

---

### 2. Lanzar el despliegue

Desde la carpeta `GCP/`:

```bash
cd GCP
./deploy.sh
```

El script pedirá el entorno a desplegar (`dev` o `prod`), mostrará el proyecto y región leídos del perfil activo, y pedirá confirmación antes de continuar.

#### Fases del despliegue

| Fase | Descripción |
|------|-------------|
| **Phase 0** | Habilita las APIs de GCP necesarias |
| **Phase 1** | Despliega la infraestructura base: Artifact Registry y Service Account con los permisos necesarios |
| **Phase 2** | Construye y publica la imagen Docker de la API en Artifact Registry |
| **Phase 3** | Despliega la infraestructura de datos: Cloud SQL (PostgreSQL) y Secret Manager |
| **Phase 4** | Despliega el Cloud Run de la API y captura su URL pública |
| **Phase 5** | Construye y publica la imagen Docker del Frontend (con la URL de la API integrada en el bundle) |
| **Phase 6** | Despliega el Cloud Run del Frontend |

Al finalizar, el script imprime las URLs de ambos servicios:

```
========================================
  Deployment complete!
  API:      https://tienda-de-ropa-api-dev-xxxx.run.app
  Frontend: https://tienda-de-ropa-frontend-dev-xxxx.run.app
========================================
```

---

### 3. Destruir la infraestructura (solo entorno dev)

Al finalizar el deploy en `dev`, el script ofrece la opción de destruir toda la infraestructura. También puedes lanzarlo de forma independiente:

```bash
cd GCP/envs/dev/terraform/02_app && terraform destroy -auto-approve && cd ../../../..
cd GCP/envs/dev/terraform/01_data && terraform destroy -auto-approve && cd ../../../..
cd GCP/envs/dev/terraform/00_base && terraform destroy -auto-approve && cd ../../../..
```

---

### Infraestructura desplegada

| Recurso | Nombre | Descripción |
|---------|--------|-------------|
| Artifact Registry | `tienda-de-ropa-dev` | Repositorio Docker de imágenes |
| Service Account | `tienda-de-ropa-sa-dev` | Cuenta de servicio única para todos los servicios |
| Cloud SQL | `store-postgres-instance-dev` | PostgreSQL 15 (db-f1-micro, 10 GB HDD) |
| Secret Manager | `store-dev-db-password` | Contraseña de la base de datos (generada aleatoriamente) |
| Cloud Run | `tienda-de-ropa-api-dev` | API FastAPI |
| Cloud Run | `tienda-de-ropa-frontend-dev` | Frontend React + Nginx |