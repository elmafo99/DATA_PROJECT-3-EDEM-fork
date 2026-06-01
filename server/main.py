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
from models import (ArticuloOut, CompraIn, CompraOut, SetComprasIn,
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/images", StaticFiles(directory="/app/images"), name="images")

security = HTTPBearer()

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

@app.get("/products/{id}", response_model=ArticuloOut, tags=["Artículos"])
def get_product(id: int):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT articulo_id, nombre, descripcion, estado,
                   categoria, unidad_medida, precio_unitario, url_imagen,
                   talla, es_drop, es_destacado
            FROM articulos WHERE articulo_id = %s
        """, (id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Producto no encontrado")
        return dict(zip(COLS_ARTICULO, row))
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error en /products/%s: %s", id, e)
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
@app.get("/getCompras", response_model=List[CompraOut], tags=["Transacciones"])
def get_compra_user_id(userID: str):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT transaccion_id, fecha, usuario_id, articulo_id,
                   cantidad, tipo_movimiento, coste_total
            FROM transacciones WHERE usuario_id = %s
        """, (userID,))
        rows = cur.fetchall()
        cols = ["transaccion_id", "fecha", "usuario_id", "articulo_id",
                "cantidad", "tipo_movimiento", "coste_total"]
        if not rows:
            raise HTTPException(status_code=404, detail="No hay compras para este usuario")
        return [dict(zip(cols, row)) for row in rows]
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Error en /getCompras: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)


# ─────────────────────────────────────────────────────────────
# 7. SET COMPRA
# ─────────────────────────────────────────────────────────────
@app.post("/setCompras", response_model=CompraOut, tags=["Transacciones"])
def set_compra_user_id(compra: SetComprasIn):
    conn = get_connection()
    cur = conn.cursor()
    try:
        articulo_id = int(compra.articleID)
        cantidad = float(compra.quantity)

        cur.execute("SELECT precio_unitario FROM articulos WHERE articulo_id = %s", (articulo_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="El artículo no existe")
        coste_total = float(row[0]) * cantidad

        cur.execute("""
            INSERT INTO transacciones
                (usuario_id, articulo_id, cantidad, tipo_movimiento, coste_total)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING transaccion_id, fecha, usuario_id, articulo_id,
                      cantidad, tipo_movimiento, coste_total
        """, (compra.userID, articulo_id, cantidad, "compra", coste_total))
        conn.commit()
        row = cur.fetchone()
        cols = ["transaccion_id", "fecha", "usuario_id", "articulo_id",
                "cantidad", "tipo_movimiento", "coste_total"]
        return dict(zip(cols, row))
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        logger.error("Error en /setCompras: %s", e)
        raise HTTPException(status_code=500, detail="Error interno del servidor")
    finally:
        cur.close()
        release_connection(conn)
