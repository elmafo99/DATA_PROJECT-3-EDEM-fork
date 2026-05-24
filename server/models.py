from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ArticuloOut(BaseModel):
    articulo_id: int
    nombre: Optional[str]
    descripcion: Optional[str]
    estado: Optional[str]
    categoria: Optional[str]
    unidad_medida: Optional[str]
    precio_unitario: Optional[float]
    url_imagen: Optional[str]
    talla: Optional[str]
    es_drop: Optional[bool] = False
    es_destacado: Optional[bool] = False

class CompraIn(BaseModel):
    articulo_id: int
    cantidad: float
    tipo_movimiento: str

class SetComprasIn(BaseModel):
    userID: int
    articleID: str
    quantity: str

class CompraOut(BaseModel):
    transaccion_id: int
    fecha: Optional[datetime]
    usuario_id: int
    articulo_id: int
    cantidad: float
    tipo_movimiento: Optional[str]
    coste_total: Optional[float]

class UsuarioRegister(BaseModel):
    nombre: str
    apellidos: Optional[str]
    email: str
    telefono: Optional[str]
    direccion: Optional[str]
    password: str               # la contraseña en texto plano (solo en el request)

class UsuarioLogin(BaseModel):
    email: str
    password: str

class UsuarioOut(BaseModel):
    usuario_id: int
    nombre: str
    apellidos: Optional[str]
    email: str
    telefono: Optional[str]
    direccion: Optional[str]
    fecha_registro: Optional[datetime]
    # NUNCA se incluye password_hash aquí

class TokenOut(BaseModel):
    access_token: str
    token_type: str             # siempre "bearer"
    usuario: UsuarioOut