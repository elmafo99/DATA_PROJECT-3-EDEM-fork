# Migración GCP -> AWS (store, eu-north-1)

Estado al **2026-06-14**. Cuenta AWS `538675137535`, región `eu-north-1`. Origen GCP: proyecto `edem-ejercicio-2526`, Cloud SQL `34.38.49.121`.

## Resumen

La infraestructura objetivo en AWS está **desplegada y parcialmente operativa**. La API ya sirve tráfico contra una RDS Postgres propia. La replicación lógica GCP -> RDS está **activa y al día** (`caught_up=t`, las 3 tablas en `srsubstate='r'`, gap de `articulos` resuelto). El frontend AWS aún no está desplegado (ECR vacío, sin servicio ECS).

## Infraestructura desplegada (Terraform, `AWS/envs/prod/eu-north-1`)

| Módulo | Recursos | Estado |
|---|---|---|
| `network` | VPC, 2 subnets públicas + 2 privadas, IGW, NAT (1 EIP `13.51.77.59`) | ✅ up |
| `database` | RDS Postgres 15 `db.t4g.micro`, single-AZ, SG restringido a VPC CIDR | ✅ `available`, endpoint `store-prod-db.c7aqc2awunu9.eu-north-1.rds.amazonaws.com:5432` |
| `ecr` | Repos `store-prod-api`, `store-prod-frontend`, `store-prod-db-init` | ✅ creados |
| `compute` | ECS cluster `store-prod-cluster`, ALB API (ALB frontend condicional a `deploy_frontend`), task defs api/frontend/db-init/migration-sub | ⚠️ ver detalle |
| `iam` | ~~Rol `store-prod-terraform-deploy`~~ | **ELIMINADO (2026-06-14)**, ver Bloqueador 4 |

### ECS / servicios

- **API** (`store-prod-api`): servicio ACTIVE, 1/1 running. Imagen en ECR (`latest`, pusheada 2026-06-12).
  - `http://store-prod-api-alb-1930283675.eu-north-1.elb.amazonaws.com/ping` -> **200 OK**
  - Antes del fix de hoy, el health check apuntaba a `/` (404 en FastAPI) -> la tarea anterior murió por fallo de health check ECS (18:33). Corregido a `/ping`.
- **Frontend**: servicio **no existe** (`deploy_frontend=false` en el último apply). ECR `store-prod-frontend` está **vacío**.
  - ~~ALB frontend (`store-prod-frontend-alb-122802516...`)~~ → **ELIMINADO (2026-06-14)**, ver Bloqueador 5. Se recrea en Phase 4/5 vía `terraform apply -var deploy_frontend=true`.
- **db-init**: imágenes en ECR (`latest` + `subscription`), corrida ya ejecutada.

### Replicación lógica GCP -> RDS (`migration-tmp/`)

Pieza que el código de `AWS/` no referenciaba en el último review, pero **ya está corriendo fuera del módulo `compute` versionado** (task definition `store-prod-migration-sub`, log group `/ecs/store-prod-migration-sub`). Secret `store-prod-gcp-repl-password` ya existe en Secrets Manager.

Estado final (2026-06-14, tras fix del gap `articulos` — ver sección de diagnóstico más abajo):

```
RDS counts:        usuarios=1  articulos=9  transacciones=0
GCP counts:        usuarios=1  articulos=9  transacciones=0
Subscription "migracion_sub": caught_up = t, srsubstate='r' en las 3 tablas
```

El gap de `articulos` (0 vs 63) está **resuelto**. El número correcto eran **9** productos (no 63 — las 63 filas en GCP eran 9 productos × 7 copias duplicadas accidentales, ya limpiadas en GCP). La corrida anterior con exit code 1 (18:45 del 2026-06-13) era un diagnóstico antiguo, no un bug nuevo — ver sección de diagnóstico.

## Fixes aplicados hoy (terraform apply, 0 recursos nuevos/destruidos, 3 in-place)

1. `AWS/modules/compute/main.tf` — health check del target group API: `path "/"` -> `"/ping"` + `matcher = "200"` explícito. Sin esto el ALB nunca marca la tarea healthy.
2. `AWS/modules/iam/main.tf` — ARNs de la policy `deploy` (S3/DynamoDB) apuntaban a `store-prod-tfstate*` / `store-prod-tfstate-lock` (no existen). Corregido a los nombres reales del bootstrap: `store-tfstate-eu-north-1` / `store-tfstate-lock`.

### Efecto secundario del fix #1/#2 y nuevo fix (PENDIENTE DE APLICAR)

El `terraform apply` de los fixes 1-2 reescribió la policy `execution_secrets` del módulo `compute` calculándola solo desde `var.api_secrets` + `var.db_init_secrets`. Esto **eliminó** un ARN que existía ahí por drift manual: `store-prod-gcp-repl-password-jvVCFn` (el secret que usa la task `store-prod-migration-sub` para conectarse a GCP). Confirmado al correr una task de diagnóstico (2 SELECT, autorizado por el usuario):

```text
ResourceInitializationError: ... AccessDeniedException: 
role/store-prod-ecs-execution is not authorized to perform: 
secretsmanager:GetSecretValue on resource: 
.../secret:store-prod-gcp-repl-password-jvVCFn
```

**Fix 3 — APLICADO (2026-06-13)**: nueva variable `migration_secrets` en `AWS/modules/compute/variables.tf`, incluida en `data.aws_iam_policy_document.secrets_read` (`AWS/modules/compute/main.tf`). Wireada en `AWS/envs/prod/eu-north-1/main.tf` con el ARN del secret de replicación. `terraform apply` aplicado: 1 cambio in-place, la policy `execution_secrets` ahora incluye ambos ARNs (`rds!db-...` y `gcp-repl-password`). Confirmado con corrida exitosa de la task `migration-sub` (exit 0).

## Diagnóstico del gap `articulos` (en curso, 2026-06-13)

Investigación paso a paso (todas las queries fueron SELECT, autorizadas por el usuario antes de correr):

1. **`pg_subscription_rel` (RDS)**: `usuarios` y `articulos` en estado `srsubstate='d'` (tablesync no completado, "data copy in progress"). Solo `transacciones` está `r` (ready).
2. **`pg_publication_tables` (GCP)**: `migracion_pub` SÍ incluye las 3 tablas (`usuarios`, `articulos`, `transacciones`) — no es un problema de publication incompleta.
3. **`pg_stat_subscription` (RDS)**: solo **1** worker de tablesync activo (`relid=16442`), con `last_msg_receipt_time` estancado (~5h sin avanzar) — **worker colgado**. El tablesync worker de la segunda tabla pendiente ni siquiera está corriendo (terminó/crasheó silenciosamente).
4. **Replica identity / PK (RDS)**: las 3 tablas tienen `relreplident='d'` (default) y PK — no es problema de esquema/identity.

**Causa raíz**: 2 tablesync workers (para `usuarios` y `articulos`) quedaron atascados/muertos tras la recreación de la suscripción (18:38). `transacciones` sincronizó bien (tabla vacía en ambos lados, trivial). Las tablas con datos reales nunca completaron el `COPY` inicial.

**Fix en curso — procedimiento de 4 pasos** (acordado con el usuario, requiere escribir en GCP y RDS):

1. GCP: `ALTER PUBLICATION migracion_pub DROP TABLE usuarios, articulos;`
2. RDS: `ALTER SUBSCRIPTION migracion_sub REFRESH PUBLICATION;` (limpia el estado de sync atascado de esas 2 tablas)
3. GCP: `ALTER PUBLICATION migracion_pub ADD TABLE usuarios, articulos;`
4. RDS: `ALTER SUBSCRIPTION migracion_sub REFRESH PUBLICATION;` (relanza tablesync con `COPY` desde cero para esas 2 tablas)

**Bloqueador 1 (resuelto, 2026-06-14)**: paso 1 falló con `ERROR: must be owner of publication migracion_pub` — `repl_user` no era owner. Resuelto manualmente por el usuario en GCP Cloud SQL (`34.38.49.121`, db `store_db`, como `store_admin`):

```sql
GRANT repl_user TO store_admin;
ALTER PUBLICATION migracion_pub OWNER TO repl_user;
REVOKE repl_user FROM store_admin;
```

Confirmado: `pubowner` ahora es `repl_user`.

**Bloqueador 2 (NUEVO, 2026-06-14) — el procedimiento de 4 pasos no aplica**: al correr paso 1 (`ALTER PUBLICATION migracion_pub DROP TABLE usuarios, articulos;`) vía task `migration-sub` con override de comando, falló:

```
ERROR:  publication "migracion_pub" is defined as FOR ALL TABLES
DETAIL:  Tables cannot be added to or dropped from FOR ALL TABLES publications.
```

`migracion_pub` es `FOR ALL TABLES` (incluye automáticamente toda tabla del esquema, presente o futura) — no se le pueden añadir/quitar tablas individualmente. Esto **no es la causa del gap**: la publication ya cubre `usuarios`/`articulos`/`transacciones` sin necesidad de listarlas.

El gap real sigue siendo: 2 tablesync workers de la subscription en RDS quedaron `srsubstate='d'` (copia inicial nunca completada) y no se reinician solos con `REFRESH PUBLICATION` (refresh solo detecta tablas *nuevas/quitadas* de la publication, no relanza syncs ya iniciados y atascados).

**Fix aplicado (2026-06-14)**: recreada la subscription en RDS (`DROP SUBSCRIPTION` + `CREATE SUBSCRIPTION ... WITH (copy_data = true)`, vía task `migration-sub`, exit 0, slot recreado). **Causa raíz real encontrada en `postgresql.log` de RDS**: los tablesync workers de `usuarios` y `articulos` SÍ arrancan (cada ~5s, reintento del launcher), pero fallan inmediatamente:

```
ERROR:  duplicate key value violates unique constraint "articulos_nombre_key"
DETAIL:  Key (nombre)=(Camiseta vintage negra) already exists.
CONTEXT:  COPY articulos, line 10

ERROR:  duplicate key value violates unique constraint "usuarios_pkey"
DETAIL:  Key (usuario_id)=(1) already exists.
CONTEXT:  COPY usuarios, line 1
```

**Diagnóstico**: las tablas `usuarios`/`articulos` en RDS ya tienen filas (probablemente seed data del job `db-init` / `01-schema.sql`, que inserta productos de ejemplo incluyendo "Camiseta vintage negra" y un usuario `usuario_id=1`). El tablesync de logical replication hace `COPY` directo sin `TRUNCATE` previo de la tabla destino salvo que la tabla esté vacía — al chocar con filas preexistentes con la misma PK/unique key, el `COPY` falla, el worker muere con exit 1, el launcher lo reintenta cada 5s, loop infinito (visible en el log: reintentos cada ~5s desde 10:04:41 hasta al menos 10:05:28).

`(SELECT count(*) FROM articulos)` devolvió `0` porque esa transacción de lectura corrió ANTES de que el primer `COPY` insertara las primeras 9 filas (que luego quedan en una transacción abortada por el error de la fila 10 → rollback → vuelve a 0... pero la fila preexistente "Camiseta vintage negra" sigue ahí desde antes, fuera de esa transacción).

**Fix aplicado (2026-06-14)**: `TRUNCATE usuarios, articulos, transacciones CASCADE` en RDS (exit 0). Resultado parcial:

- `usuarios`: ✅ resuelto. `count=1`, `srsubstate='r'`.
- `transacciones`: ✅ ya estaba `'r'` (tabla vacía).
- `articulos`: ❌ sigue fallando, MISMO error tras el truncate (`duplicate key ... "Camiseta vintage negra" ... COPY articulos, line 10`), con la tabla RDS vacía.

**Causa raíz REAL (encontrada, 2026-06-14)** — no es un problema de RDS ni de la subscription. Es un problema de **datos en el origen GCP**:

```sql
-- GCP store_db.articulos
SELECT nombre, count(*) FROM articulos GROUP BY nombre HAVING count(*)>1;
```

```
           nombre            | count
-----------------------------+-------
 Camiseta grafica roja       |     7
 Zapatilla Runner Beige      |     7
 Zapatilla Blanca Multicolor |     7
 Camiseta streetwear blanca  |     7
 Zapatilla Clásica Blanca    |     7
 Zapatilla Verde Gamba       |     7
 Camiseta vintage negra      |     7
 Camiseta retro azul         |     7
 Zapatilla Basket Azul       |     7
(9 rows)
-- total count(*) = 63
```

`articulos` en GCP tiene **9 productos distintos, cada uno duplicado 7 veces = 63 filas**. El esquema de GCP NO tiene `UNIQUE(nombre)` (o lo tiene pero ya tenía estas filas de antes). El esquema de RDS (`init-db/01-schema.sql`) SÍ tiene `articulos.nombre UNIQUE`. El `COPY` del tablesync inserta fila a fila dentro de una transacción: al llegar a la fila 10 (= 2ª copia de "Camiseta vintage negra", la 1ª ya insertada como fila 1), choca con el `UNIQUE` de RDS → toda la transacción de COPY hace rollback → el worker muere → reintenta cada 5s → mismo resultado, loop infinito.

**Las 63 filas "esperadas" en GCP en realidad son 9 productos × 7 copias accidentales** (probablemente el seed `01-schema.sql` se corrió 7 veces contra GCP sin que `ON CONFLICT (nombre) DO NOTHING` aplicara — posible si el `UNIQUE` no existe en el esquema de GCP). Esto es un problema de calidad de datos en el origen, no del pipeline de replicación.

**Fix aplicado y RESUELTO (2026-06-14)**: opción 1 — limpieza de GCP. `store_admin` otorgó temporalmente `GRANT DELETE, SELECT ON articulos TO repl_user`. Vía task `migration-sub`:

```sql
DELETE FROM articulos a USING articulos b WHERE a.nombre = b.nombre AND a.articulo_id > b.articulo_id;
-- DELETE 54
```

GCP `articulos` quedó con 9 filas (1 por producto, sin duplicados). `transacciones` en GCP estaba vacía (0 filas) — sin FKs rotas por el DELETE.

**Verificación final en RDS** (vía `migration-sub`, todas las queries autorizadas):

```
 usuarios | articulos | transacciones
----------+-----------+---------------
        1 |         9 |             0

    srrelid    | srsubstate
---------------+------------
 transacciones | r
 articulos     | r
 usuarios      | r

    subname    | caught_up
---------------+-----------
 migracion_sub | t
```

**Gap `articulos` CERRADO**. El número correcto era **9** (no 63 — las 63 filas originales eran 9 productos × 7 copias accidentales, dato corrupto en GCP). Las 3 tablas en `srsubstate='r'` (ready), subscription `caught_up=t`.

**Pendiente de limpieza (no bloqueante)**: revocar el permiso temporal en GCP — `REVOKE DELETE, SELECT ON articulos FROM repl_user;` (correr manualmente como `store_admin`, mismo patrón que el `ALTER PUBLICATION ... OWNER`).

### Bloqueador 3 (RESUELTO, 2026-06-14) — `migration-sub` traído a terraform

Item 1 de la lista de pendientes del usuario: `store-prod-migration-sub` (task definition + log group) se había creado manualmente vía `aws ecs register-task-definition` / `aws logs create-log-group`, fuera de `AWS/modules/compute`. Riesgo: cualquier `apply` futuro sobre `module.compute` no lo gestionaba, y un cambio en `execution_secrets` ya había roto el acceso al secret `GCP_REPL_PASSWORD` una vez (ver incidente arriba).

Fix:

- `AWS/modules/compute/main.tf`: nuevo `aws_cloudwatch_log_group.migration_sub` (`/ecs/store-prod-migration-sub`, retention 14d) + nuevo `aws_ecs_task_definition.migration_sub` (container `migration-sub`, imagen `${ecr db-init}:subscription`, env vars `DB_HOST/DB_USER/DB_NAME/DB_PORT/GCP_HOST`, secrets `DB_PASSWORD` + `GCP_REPL_PASSWORD`, logs al nuevo log group).
- `AWS/modules/compute/variables.tf`: nuevas variables `migration_sub_image`, `migration_sub_env_vars` (más `migration_secrets` ya existente, reescrito en el mismo bloque).
- `AWS/envs/prod/eu-north-1/main.tf`: pasa `migration_sub_image = "${ecr db-init}:subscription"` y `migration_sub_env_vars` (con `GCP_HOST = local.gcp_db_public_ip`).
- Log group existente importado a state (`terraform import module.compute.aws_cloudwatch_log_group.migration_sub /ecs/store-prod-migration-sub`) para evitar `ResourceAlreadyExistsException`.
- Efecto colateral encontrado durante el plan: `deploy_frontend` por defecto es `true` (módulo y variable env), pero la infra viva lo tenía en `false` vía `-var` no persistido — el plan amenazaba con crear `aws_ecs_service.frontend[0]`. Fijado permanentemente en `AWS/envs/prod/eu-north-1/terraform.tfvars` (gitignored) con `deploy_frontend = false` hasta Phase 4/5.

`terraform apply` aplicado: 1 to add (task definition, ahora revisión 2), 1 to change (log group: retention 0→14, tags). `terraform plan` posterior con `-var="deploy_frontend=false"`: **No changes** — sin drift.

### Bloqueador 4 (RESUELTO, 2026-06-14) — rol `store-prod-terraform-deploy` eliminado

Items 4 y 6 de la lista de pendientes del usuario. Confirmado que `deploy.sh` corre `terraform apply` con la identidad CLI directa (`arn:aws:iam::538675137535:user/terraform-cli`, vía `aws sts get-caller-identity`), nunca asume `store-prod-terraform-deploy`. El rol existía solo en `module.iam`, sin uso, con `resources=["*"]` en `rds:*`, `ecs:*`, `ecr:*`, `secretsmanager:*`, `elasticloadbalancing:*`, `logs:*` — superficie de ataque latente sin beneficio.

Fix: eliminado por completo.

- `AWS/envs/prod/eu-north-1/main.tf`: quitado el bloque `module "iam"`.
- `AWS/envs/prod/eu-north-1/outputs.tf`: quitado `output "deploy_role_arn"`.
- `AWS/envs/prod/eu-north-1/variables.tf` y `terraform.tfvars`: quitada `trusted_principal_arns` (solo la consumía `module.iam`).
- `AWS/modules/iam/` queda sin referencias (módulo no borrado del filesystem, pero no instanciado).

`terraform apply`: 0 to add, 0 to change, **2 to destroy** (`aws_iam_role.deploy`, `aws_iam_role_policy.deploy`). Verificado: `aws iam get-role --role-name store-prod-terraform-deploy` → `NoSuchEntity`. `terraform plan` posterior: **No changes**.

### Bloqueador 5 (RESUELTO, 2026-06-14) — ALB frontend hecho condicional

Item 5 de la lista de pendientes del usuario. `aws_lb.frontend`, `aws_lb_target_group.frontend` y `aws_lb_listener.frontend` se creaban **incondicionalmente** en `module.compute`, aunque `aws_ecs_service.frontend` ya estaba gateado por `var.deploy_frontend`. Resultado: ALB activo desde Phase 1 (~2026-06-12) sin ningún target, costo innecesario durante toda la ventana de migración.

Fix: `AWS/modules/compute/main.tf` — añadido `count = var.deploy_frontend ? 1 : 0` a las 3 resources (`aws_lb.frontend`, `aws_lb_target_group.frontend`, `aws_lb_listener.frontend`), referencias actualizadas a `[0]` (incluyendo `aws_ecs_service.frontend.load_balancer.target_group_arn`). `AWS/modules/compute/outputs.tf` — `frontend_url`, `frontend_alb_dns_name`, `frontend_alb_zone_id` devuelven `null` cuando `deploy_frontend=false`.

`terraform apply`: 0 to add, 0 to change, **3 to destroy** (`aws_lb.frontend[0]`, `aws_lb_target_group.frontend[0]`, `aws_lb_listener.frontend[0]`). `frontend_url` output ahora `null`. `terraform plan` posterior: **No changes**. El ALB se recreará automáticamente en Phase 4/5 al pasar `deploy_frontend=true`.

### Bloqueador 6 (RESUELTO, 2026-06-14) — mejoras post-deploy del audit (7 items)

Tras Phase 4/5 (frontend desplegado), análisis general → 15 hallazgos priorizados. De ellos, 7 implementados directamente (resto: ver "Pendiente"/"Qué se puede mejorar" o ya resueltos antes):

- **SG scoping** — `aws_security_group.ecs_tasks` tenía una sola regla ingress 0-65535 desde el SG de los ALBs. Sustituida por 2 reglas scoped: puerto `var.api_container_port` (API) y `var.frontend_container_port` (frontend), ambas `from = aws_security_group.alb.id`. Reduce superficie de movimiento lateral dentro de la VPC.
- **Secret ARN por nombre, no hardcoded** — `GCP_REPL_PASSWORD` estaba hardcoded como `arn:...secret:store-prod-gcp-repl-password-jvVCFn` en `envs/prod/eu-north-1/main.tf`. Ahora `data "aws_secretsmanager_secret" "gcp_repl_password" { name = "store-prod-gcp-repl-password" }`, referenciado vía `.arn`. Evita rotura si el secret se recrea y AWS regenera el sufijo `-xxxxxx`.
- **ECS deployment circuit breaker** — añadido `deployment_circuit_breaker { enable = true, rollback = true }` a `aws_ecs_service.api` y `aws_ecs_service.frontend`. Rollback automático si un deploy deja el servicio con 0 tasks running.
- **Health check matcher frontend** — `aws_lb_target_group.frontend.health_check` ahora con `matcher = "200"` explícito, igual que el TG de la API.
- **`migration-tmp/` → `db-init/subscription/`** — directorio temporal (`Dockerfile` + `create_sub.sh`, no trackeado) movido a `db-init/subscription/` (trackeado). `AWS/deploy.sh` documenta al final cómo rebuildear/pushear la imagen `:subscription` y lanzar el task `store-prod-migration-sub` si hace falta.
- **`init-db/02-schema-only.sql` eliminado** — scratch file sin uso (de la investigación del gap `articulos`, ya resuelto), no referenciado por `deploy.sh` ni `db-init/Dockerfile`.
- **`AWS/modules/iam/` eliminado** — directorio huérfano tras el fix de items 4/6 (rol `store-prod-terraform-deploy` ya borrado, `module.iam` ya no se instanciaba).

`terraform apply`: 3 changed (SG, ambos circuit breakers, health check matcher, secret ARN — todo en un solo plan), 0 errors. Servicios `store-prod-api` y `store-prod-frontend` siguen 1/1 healthy post-apply.

Nota: el comentario en `envs/prod/eu-north-1/main.tf` sobre `GCP_REPL_PASSWORD` aún dice "ver migration-tmp/" — debería actualizarse a `db-init/subscription/` en el próximo pase.

## Pendiente para completar la migración

1. ~~Investigar y resolver gap de `articulos`~~ → **RESUELTO (2026-06-14)**. Causa real: 9 productos × 7 duplicados accidentales en GCP (63 filas), `UNIQUE(nombre)` en RDS bloqueaba el COPY inicial. Fix: subscription recreada + RDS truncado + 54 duplicados borrados en GCP. Estado final: `articulos=9`, las 3 tablas `srsubstate='r'`, `caught_up=t`. Cleanup `REVOKE DELETE, SELECT ON articulos FROM repl_user` en GCP: **hecho**.
2. ~~Build + push imagen frontend~~ → **RESUELTO (2026-06-14)**. Imagen `store-prod-frontend:latest` con `VITE_API_URL=http://store-prod-api-alb-1930283675.eu-north-1.elb.amazonaws.com` (Phase 4).
3. ~~Apply final con `deploy_frontend=true`~~ → **RESUELTO (2026-06-14)** (Phase 5). 4 recursos creados (ALB+TG+listener+servicio ECS). Servicio `store-prod-frontend` 1/1 running, target registrado, ALB responde **200 OK**: `http://store-prod-frontend-alb-2124839867.eu-north-1.elb.amazonaws.com`.
4. ~~Decidir si `store-prod-migration-sub` se integra a `AWS/modules/compute`~~ → **RESUELTO (2026-06-14)**. Ver "Bloqueador 3" abajo: ahora gestionado por terraform (task def revisión 2 + log group importado).
5. Plan de cutover final: cuando RDS esté al día, apuntar DNS/tráfico real a los ALBs de AWS y desactivar la suscripción + el stack GCP. Ver checklist abajo.

### Checklist de cutover y decommission de GCP

Migración funcional: API + frontend en AWS sirviendo, replicación `caught_up=t`. Pendiente solo el corte final de tráfico hacia GCP y el apagado del stack origen. Orden recomendado:

1. **Congelar escrituras en GCP** (ventana corta): poner Cloud Run de la API GCP en modo solo-lectura o escalar a 0, para que no entren filas nuevas que la subscription no llegue a replicar.
2. **Verificar `caught_up=t`** una última vez en RDS (`SELECT * FROM pg_stat_subscription;`) tras el paso 1 — confirma que RDS tiene exactamente los mismos datos que GCP en el momento del corte.
3. **Apuntar tráfico real a AWS**: actualizar DNS (o el sistema que use el frontend público) para que apunte a `frontend_url` (`store-prod-frontend-alb-...`) en vez del Cloud Run/Load Balancer de GCP. Sin dominio propio configurado todavía — si se añade Route53, ver nota en "Qué se puede mejorar".
4. **Apagar la subscription en RDS** (ya no se necesita, AWS es ahora la fuente de verdad):

   ```sql
   ALTER SUBSCRIPTION migracion_sub DISABLE;
   DROP SUBSCRIPTION migracion_sub;
   ```

5. **Limpiar el lado GCP** (como `store_admin`):

   ```sql
   DROP PUBLICATION migracion_pub;
   DROP ROLE repl_user;
   ```

6. **Revertir config temporal de GCP Cloud SQL** (`GCP/modules/cloudsql/`, `GCP/envs/dev/terraform/01_data/cloudsql.tf`): quitar el `authorized_networks` con el NAT EIP de AWS (`13.51.77.59`) y el flag `cloudsql.logical_decoding=on` si no se usa para nada más. `terraform apply` en el stack GCP.
7. **Decommission del stack GCP**: una vez confirmado que AWS sirve tráfico real sin problemas (dejar correr unos días), `terraform destroy` o escalar a 0 los servicios Cloud Run + Cloud SQL en `edem-ejercicio-2526` para parar el billing.

**Rollback**: la subscription es unidireccional GCP→RDS. Si algo falla post-cutover y hay que volver a GCP, no hay replicación inversa — habría que restaurar desde snapshot de RDS o reconstruir manualmente los datos escritos en AWS durante la ventana. Por eso el paso 7 (decommission GCP) debe ser el último, después de validar AWS en producción real.

## Análisis general (2026-06-13)

### Lo que está bien

- **Estructura de módulos limpia**: network/database/ecr/compute/iam, cada uno con responsabilidad clara. Espejo razonable del setup GCP.
- **`deploy_frontend` flag**: resuelve bien el problema huevo-gallina de `VITE_API_URL` (ALB no existe hasta crear el módulo compute, pero el build del frontend lo necesita).
- **Costos contenidos**: 1 NAT gateway, `db.t4g.micro`, single-AZ, Fargate 256/512 — apropiado para ejercicio de migración, no sobre-provisionado.
- **RDS**: `manage_master_user_password = true` (Secrets Manager gestiona la rotación), `storage_encrypted = true`, SG limitado al CIDR de la VPC (no expuesto a internet). Bien.
- **Secrets vía `valueFrom`**: API y db-init reciben `DB_PASSWORD` sin que el password pase por variables de entorno planas ni por terraform state en texto. Patrón correcto.
- **`terraform_remote_state` de solo lectura** hacia el state GCP: mantiene los 2 stacks desacoplados durante la migración, sin mezclar states.
- **La replicación lógica RDS<->Cloud SQL ya está funcionando** (subscription `caught_up=t`, `rds.logical_replication=1` en el parameter group) — la parte más difícil de un PG->PG live-migration ya está resuelta.

### Lo que está mal / riesgos activos

1. ~~Drift no versionado: `store-prod-migration-sub` (task def, log group) creado fuera de terraform~~ → **RESUELTO (2026-06-14)**. Ver "Bloqueador 3" abajo.
2. ~~Gap de datos `articulos`~~ → **RESUELTO**. Causa real: 9 productos × 7 duplicados en GCP (sin `UNIQUE` ahí), chocaban contra el `UNIQUE(nombre)` de RDS. Limpiado en GCP (DELETE 54), subscription recreada, las 3 tablas `srsubstate='r'`, `articulos=9` en ambos lados.
3. ~~Corrida `migration-sub` con exit code 1 (18:45)~~ → explicado: era un diagnóstico antiguo (`pg_subscription_rel` SELECT) mostrando el mismo `srsubstate='d'` ya investigado en el punto 2, no un bug nuevo ni una race condition recurrente.
4. ~~Rol `store-prod-terraform-deploy` no usado, con permisos amplios `resources=["*"]"`~~ → **RESUELTO (2026-06-14)**, ver Bloqueador 4.
5. ~~2 ALBs corriendo desde Phase 1 aunque el frontend no exista todavía~~ → **RESUELTO (2026-06-14)**, ver Bloqueador 5.
6. ~~Permisos del rol deploy demasiado anchos~~ → **RESUELTO (2026-06-14)** junto con el punto 4 (rol eliminado).
7. **`.gitignore` no cubre los archivos `tfplan`** (sin extensión) — quedaron 2 sin trackear (`AWS/.../tfplan`, `GCP/.../tfplan`). Si se hace `git add -A` se commitean (contienen referencias a recursos/ARNs reales).

### Qué se puede mejorar (no bloqueante)

- Documentar/automatizar la creación de `migracion_pub` y `repl_user` en el lado GCP (hoy es manual, sin terraform ni script versionado) — sería el paso 0 de cualquier reproducción de este setup desde cero.
- `health_check.interval`/`unhealthy_threshold` del target group API son algo lentos (5×30s ≈ 2.5min para marcar unhealthy) — útil acelerar durante la fase activa de migración para feedback más rápido.
- ~~Considerar mover `store-prod-migration-sub` a un módulo terraform propio~~ → hecho, ver "Bloqueador 3".
- Plan de cutover y rollback todavía no escrito: falta decidir umbral de "RDS al día" antes de cortar tráfico, y cómo revertir si algo falla post-cutover (la suscripción es unidireccional GCP->RDS; volver atrás requeriría replicación inversa o restaurar desde snapshot).

## Referencias rápidas

- `terraform output` (desde `AWS/envs/prod/eu-north-1`) expone: `api_url`, `frontend_url`, `rds_endpoint`, `ecr_repository_urls`, `ecs_cluster_name`, `nat_eip`, `db_init_task_definition_arn`, `db_init_subnet_ids`, `db_init_security_group_id`.
- `AWS/deploy.sh` reproduce el flujo de 5 fases (Phase 1 ya aplicado salvo frontend; faltan Phase 4-5).
- `migration-tmp/Dockerfile` + `create_sub.sh`: imagen usada para `store-prod-migration-sub` (crea/verifica `SUBSCRIPTION migracion_sub`).
