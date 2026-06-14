CREATE TABLE IF NOT EXISTS usuarios (
    usuario_id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    telefono VARCHAR(20),
    direccion TEXT,
    password_hash VARCHAR(255) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS articulos (
    articulo_id SERIAL PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE,
    descripcion TEXT,
    estado VARCHAR(20),
    categoria VARCHAR(50),
    unidad_medida VARCHAR(10),
    precio_unitario NUMERIC(12, 2),
    url_imagen VARCHAR(255),
    talla VARCHAR(5),
    es_drop BOOLEAN DEFAULT FALSE,
    es_destacado BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS transacciones (
    transaccion_id SERIAL PRIMARY KEY,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usuario_id INT REFERENCES usuarios(usuario_id),
    articulo_id INT REFERENCES articulos(articulo_id),
    cantidad NUMERIC(12, 3) NOT NULL,
    tipo_movimiento VARCHAR(20),
    coste_total NUMERIC(12, 2)
);

INSERT INTO articulos
    (nombre, descripcion, estado, categoria, unidad_medida, precio_unitario, url_imagen, talla, es_drop, es_destacado)
VALUES
    (
        'Camiseta vintage negra',
        'Camiseta negra oversize con corte vintage.',
        'nuevo',
        'camisetas',
        'ud',
        24.99,
        '/images/camiseta-vintage-negra.png',
        'L',
        FALSE,
        TRUE
    ),
    (
        'Camiseta streetwear blanca',
        'Camiseta blanca de algodon con estilo urbano.',
        'nuevo',
        'camisetas',
        'ud',
        22.50,
        '/images/camiseta-streetwear-blanca.png',
        'M',
        TRUE,
        FALSE
    ),
    (
        'Camiseta retro azul',
        'Camiseta azul con inspiracion retro y fit relajado.',
        'segunda mano',
        'camisetas',
        'ud',
        18.00,
        '/images/camiseta-retro-azul.png',
        'S',
        FALSE,
        FALSE
    ),
    (
        'Camiseta grafica roja',
        'Camiseta roja con estampado grafico frontal.',
        'nuevo',
        'camisetas',
        'ud',
        27.99,
        '/images/camiseta-grafica-roja.png',
        'XL',
        TRUE,
        FALSE
    )
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO articulos
    (nombre, descripcion, estado, categoria, unidad_medida, precio_unitario, url_imagen, talla, es_drop, es_destacado)
VALUES
    (
        'Zapatilla Blanca Multicolor',
        'Zapatilla blanca con parche multicolor en tonos rosa, azul y verde. Suela gum y detalles cromáticos en el lateral.',
        'nuevo',
        'zapatillas',
        'ud',
        89.99,
        '/images/zapatilla-running-blanca.png',
        '42',
        FALSE,
        FALSE
    ),
    (
        'Zapatilla Basket Azul',
        'Zapatilla azul y gris con gran X lateral. Estilo basket urbano con suela chunky y refuerzos en ante.',
        'nuevo',
        'zapatillas',
        'ud',
        109.99,
        '/images/zapatilla-basket-negra.png',
        '41',
        TRUE,
        FALSE
    ),
    (
        'Zapatilla Runner Beige',
        'Runner retro en tonos beige, verde y naranja. Capas de tejido y ante con suela gum gruesa. Estética de los 90s.',
        'nuevo',
        'zapatillas',
        'ud',
        95.00,
        '/images/zapatilla-retro-roja.png',
        '43',
        TRUE,
        FALSE
    ),
    (
        'Zapatilla Verde Gamba',
        'Zapatilla verde intensa con H blanco lateral. Inspirada en el fútbol sala de los 80s. Suela gum y puntera reforzada.',
        'segunda mano',
        'zapatillas',
        'ud',
        55.00,
        '/images/zapatilla-urbana-gris.png',
        '40',
        FALSE,
        FALSE
    ),
    (
        'Zapatilla Clásica Blanca',
        'Silueta clásica en blanco roto con swoosh negro y suela gum caramelo. Icónica del running vintage americano.',
        'segunda mano',
        'zapatillas',
        'ud',
        72.50,
        '/images/zapatilla-vintage-azul.png',
        '44',
        FALSE,
        FALSE
    )
ON CONFLICT (nombre) DO NOTHING;
