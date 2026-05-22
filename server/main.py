import os
import logging
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from database import get_connection, release_connection
from models import (ArticuloOut, CompraIn, CompraOut,
                    UsuarioRegister, UsuarioLogin, UsuarioOut, TokenOut)
from auth import hash_password, verify_password, create_access_token, decode_token
from typing import List, Optional

logger = logging.getLogger(__name__)

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="Vintage & Streetwear API",
    description="API para la tienda de ropa vintage y streetwear",
    version="2.0.0"
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

_cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/images", StaticFiles(directory="/app/images"), name="images")

security = HTTPBearer()

@app.on_event("startup")
def init_db():
    conn = get_connection()
    cur = conn.cursor()
    try:
        schema_path = os.path.join(os.path.dirname(__file__), "01-schema.sql")
        with open(schema_path, "r") as f:
            cur.execute(f.read())
        conn.commit()
        logger.info("Schema initialized successfully")
    except Exception as e:
        conn.rollback()
        logger.error("Error initializing schema: %s", e)
    finally:
        cur.close()
        release_connection(conn)

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = decode_token(credentials.credentials)
        return payload
    except ValueError:
        raise HTTPException(status_code=401, detail="Token inválido o expirado")


# ─────────────────────────────────────────────────────────────
# 1. PING-PONG
# ─────────────────────────────────────────────────────────────
@app.get("/ping", tags=["Health"])
def ping_pong():
    return {"status": "pong"}


# ─────────────────────────────────────────────────────────────
# 2. REGISTRO
# ─────────────────────────────────────────────────────────────
@app.post("/register", response_model=TokenOut, tags=["Usuarios"])
@limiter.limit("3/minute")
def register(request: Request, usuario: UsuarioRegister):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT usuario_id FROM usuarios WHERE email = %s", (usuario.email,))
        if cur.fetchone():
            raise HTTPException(status_code=400, detail="El email ya está registrado")

        password_hash = hash_password(usuario.password)

        cur.execute("""
            INSERT INTO usuarios (nombre, apellidos, email, telefono, direccion, password_hash)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING usuario_id, nombre, apellidos, email, telefono, direccion, fecha_registro
        """, (usuario.nombre, usuario.apellidos, usuario.email,
              usuario.telefono, usuario.direccion, password_hash))
        conn.commit()
        row = cur.fetchone()
        cols = ["usuario_id", "nombre", "apellidos", "email", "telefono", "direccion", "fecha_registro"]
        usuario_data = dict(zip(cols, row))

        token = create_access_token({"usuario_id": usuario_data["usuario_id"], "email": usuario_data["email"]})
        return {"access_token": token, "token_type": "bearer", "usuario": usuario_data}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        logger.error("Error en /register: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 3. LOGIN
# ─────────────────────────────────────────────────────────────
@app.post("/login", response_model=TokenOut, tags=["Usuarios"])
@limiter.limit("5/minute")
def login(request: Request, credenciales: UsuarioLogin):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT usuario_id, nombre, apellidos, email, telefono, direccion, fecha_registro, password_hash
            FROM usuarios WHERE email = %s
        """, (credenciales.email,))
        row = cur.fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Email o contraseña incorrectos")

        cols = ["usuario_id", "nombre", "apellidos", "email", "telefono", "direccion", "fecha_registro", "password_hash"]
        usuario_data = dict(zip(cols, row))

        if not verify_password(credenciales.password, usuario_data["password_hash"]):
            raise HTTPException(status_code=401, detail="Email o contraseña incorrectos")

        token = create_access_token({"usuario_id": usuario_data["usuario_id"], "email": usuario_data["email"]})
        usuario_data.pop("password_hash")
        return {"access_token": token, "token_type": "bearer", "usuario": usuario_data}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error en /login: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 4. PERFIL
# ─────────────────────────────────────────────────────────────
@app.get("/me", response_model=UsuarioOut, tags=["Usuarios"])
def get_me(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT usuario_id, nombre, apellidos, email, telefono, direccion, fecha_registro
            FROM usuarios WHERE usuario_id = %s
        """, (current_user["usuario_id"],))
        row = cur.fetchone()
        cols = ["usuario_id", "nombre", "apellidos", "email", "telefono", "direccion", "fecha_registro"]
        return dict(zip(cols, row))
    except Exception as e:
        logger.error("Error en /me: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 5. GET ARTICULOS
# ─────────────────────────────────────────────────────────────
COLS_ARTICULO = ["articulo_id", "nombre", "descripcion", "estado",
                 "categoria", "unidad_medida", "precio_unitario", "url_imagen",
                 "talla", "es_drop", "es_destacado"]

@app.get("/getArticulos", response_model=List[ArticuloOut], tags=["Artículos"])
def get_articulos(talla: Optional[str] = None, estado: Optional[str] = None):
    conn = get_connection()
    cur = conn.cursor()
    try:
        conditions, params = [], []
        if talla:
            conditions.append("talla = %s")
            params.append(talla)
        if estado:
            conditions.append("estado = %s")
            params.append(estado)
        where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
        cur.execute(f"""
            SELECT articulo_id, nombre, descripcion, estado,
                   categoria, unidad_medida, precio_unitario, url_imagen,
                   talla, es_drop, es_destacado
            FROM articulos {where}
        """, params)
        rows = cur.fetchall()
        return [dict(zip(COLS_ARTICULO, row)) for row in rows]
    except Exception as e:
        logger.error("Error en /getArticulos: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 5b. GET DROPS
# ─────────────────────────────────────────────────────────────
@app.get("/getDrops", response_model=List[ArticuloOut], tags=["Artículos"])
def get_drops():
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT articulo_id, nombre, descripcion, estado,
                   categoria, unidad_medida, precio_unitario, url_imagen,
                   talla, es_drop, es_destacado
            FROM articulos WHERE es_drop = TRUE
        """)
        rows = cur.fetchall()
        return [dict(zip(COLS_ARTICULO, row)) for row in rows]
    except Exception as e:
        logger.error("Error en /getDrops: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 5c. GET DESTACADO
# ─────────────────────────────────────────────────────────────
@app.get("/getDestacado", response_model=ArticuloOut, tags=["Artículos"])
def get_destacado():
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT articulo_id, nombre, descripcion, estado,
                   categoria, unidad_medida, precio_unitario, url_imagen,
                   talla, es_drop, es_destacado
            FROM articulos WHERE es_destacado = TRUE LIMIT 1
        """)
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="No hay producto destacado")
        return dict(zip(COLS_ARTICULO, row))
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error en /getDestacado: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 6. GET COMPRAS
# ─────────────────────────────────────────────────────────────
@app.get("/getCompraUserId", response_model=List[CompraOut], tags=["Transacciones"])
def get_compra_user_id(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT transaccion_id, fecha, usuario_id, articulo_id,
                   cantidad, tipo_movimiento, coste_total
            FROM transacciones WHERE usuario_id = %s
        """, (current_user["usuario_id"],))
        rows = cur.fetchall()
        cols = ["transaccion_id", "fecha", "usuario_id", "articulo_id",
                "cantidad", "tipo_movimiento", "coste_total"]
        if not rows:
            raise HTTPException(status_code=404, detail="No hay compras para este usuario")
        return [dict(zip(cols, row)) for row in rows]
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error en /getCompraUserId: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 7. SET COMPRA
# ─────────────────────────────────────────────────────────────
@app.post("/setCompraUserId", response_model=CompraOut, tags=["Transacciones"])
def set_compra_user_id(compra: CompraIn, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    cur = conn.cursor()
    try:
        # Precio calculado desde la BD — nunca se confía en el cliente
        cur.execute("SELECT precio_unitario FROM articulos WHERE articulo_id = %s", (compra.articulo_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="El artículo no existe")
        coste_total = float(row[0]) * compra.cantidad

        cur.execute("""
            INSERT INTO transacciones
                (usuario_id, articulo_id, cantidad, tipo_movimiento, coste_total)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING transaccion_id, fecha, usuario_id, articulo_id,
                      cantidad, tipo_movimiento, coste_total
        """, (current_user["usuario_id"], compra.articulo_id,
              compra.cantidad, compra.tipo_movimiento, coste_total))
        conn.commit()
        row = cur.fetchone()
        cols = ["transaccion_id", "fecha", "usuario_id", "articulo_id",
                "cantidad", "tipo_movimiento", "coste_total"]
        return dict(zip(cols, row))
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        logger.error("Error en /setCompraUserId: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)
