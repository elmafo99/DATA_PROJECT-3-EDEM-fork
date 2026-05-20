import { useState, useEffect } from 'react';
import Auth from './Auth';

function ProductCard({ art, badge, esFav, onFavorito, onAnadir }) {
  return (
    <div className="group cursor-pointer flex flex-col h-full">
      <div className="relative aspect-[3/4] bg-[#EBE7E0] overflow-hidden mb-6">
        {badge && (
          <span className="absolute top-4 left-4 z-10 bg-[#8B7355] text-[#F7F5F0] text-[10px] uppercase tracking-widest px-3 py-1">
            {badge}
          </span>
        )}
        <button
          onClick={onFavorito}
          className="absolute top-4 right-4 z-10 text-2xl transition-transform hover:scale-110 opacity-0 group-hover:opacity-100"
        >
          {esFav ? '❤️' : '🤍'}
        </button>
        <img
          src={`${import.meta.env.VITE_API_URL}${art.url_imagen}`}
          alt={art.nombre}
          className="w-full h-full object-cover mix-blend-multiply group-hover:scale-105 group-hover:sepia-[0.2] transition-all duration-700 ease-in-out"
        />
        <span className="absolute bottom-0 left-0 bg-[#2C241B] text-[#F7F5F0] text-[10px] uppercase tracking-widest px-3 py-1 m-4">
          {art.estado}
        </span>
      </div>
      <div className="flex flex-col flex-grow">
        <h3 className="text-sm font-semibold uppercase tracking-wider mb-1 text-[#2C241B]">{art.nombre}</h3>
        {art.talla && <p className="text-xs text-stone-500 uppercase tracking-widest mb-2">Talla {art.talla}</p>}
        <div className="flex justify-between items-end mt-auto">
          <span className="font-serif text-lg text-[#5C4A3D]">{art.precio_unitario}€</span>
          <button
            onClick={onAnadir}
            className="text-xs uppercase tracking-widest border-b border-[#2C241B] pb-0.5 hover:text-[#8B7355] hover:border-[#8B7355] transition-colors"
          >
            Añadir
          </button>
        </div>
      </div>
    </div>
  );
}

function App() {
  const [articulos, setArticulos] = useState([]);
  const [cargando, setCargando] = useState(true);
  const [mostrarAuth, setMostrarAuth] = useState(false);
  const [usuario, setUsuario] = useState(null);
  const [carrito, setCarrito] = useState([]);
  const [mostrarCarrito, setMostrarCarrito] = useState(false);
  const [favoritos, setFavoritos] = useState([]);
  const [filtroTalla, setFiltroTalla] = useState(null);
  const [filtroEstado, setFiltroEstado] = useState(null);

  useEffect(() => {
    const usuarioGuardado = localStorage.getItem('usuario');
    if (usuarioGuardado) setUsuario(JSON.parse(usuarioGuardado));
    const carritoGuardado = localStorage.getItem('carrito');
    if (carritoGuardado) setCarrito(JSON.parse(carritoGuardado));
    const favsGuardados = localStorage.getItem('favoritos');
    if (favsGuardados) setFavoritos(JSON.parse(favsGuardados));

    fetch(`${import.meta.env.VITE_API_URL}/getArticulos`)
      .then(res => res.json())
      .then(data => { setArticulos(Array.isArray(data) ? data : []); setCargando(false); })
      .catch(err => { console.error("Error:", err); setCargando(false); });
  }, []);

  useEffect(() => { localStorage.setItem('carrito', JSON.stringify(carrito)); }, [carrito]);
  useEffect(() => { localStorage.setItem('favoritos', JSON.stringify(favoritos)); }, [favoritos]);

  const cerrarSesion = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('usuario');
    setUsuario(null);
  };

  const toggleFavorito = (id) =>
    setFavoritos(prev => prev.includes(id) ? prev.filter(f => f !== id) : [...prev, id]);

  const añadirAlCarrito = (articulo) => setCarrito(prev => [...prev, articulo]);

  const comprarCarrito = async () => {
    if (!usuario) { setMostrarCarrito(false); setMostrarAuth(true); return; }
    const token = localStorage.getItem('token');
    let errores = 0;
    for (const item of carrito) {
      try {
        const res = await fetch(`${import.meta.env.VITE_API_URL}/setCompraUserId`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ articulo_id: item.articulo_id, cantidad: 1, tipo_movimiento: "venta", coste_total: item.precio_unitario }),
        });
        if (!res.ok) errores++;
      } catch { errores++; }
    }
    if (errores === 0) {
      alert("Su compra se ha procesado con elegancia. ¡Gracias!");
      setCarrito([]);
      setMostrarCarrito(false);
    } else {
      alert("Hubo un contratiempo con su pedido. Inténtelo de nuevo.");
    }
  };

  const totalCarrito = carrito.reduce((sum, item) => sum + parseFloat(item.precio_unitario), 0).toFixed(2);

  // Datos derivados
  const destacado = articulos.find(a => a.es_destacado);
  const drops = articulos.filter(a => a.es_drop);
  const tallas = [...new Set(articulos.map(a => a.talla).filter(Boolean))].sort();
  const estados = [...new Set(articulos.map(a => a.estado).filter(Boolean))];

  const articulosFiltrados = articulos.filter(a => {
    if (filtroTalla && a.talla !== filtroTalla) return false;
    if (filtroEstado && a.estado !== filtroEstado) return false;
    return true;
  });

  const toggleFiltroTalla = (t) => setFiltroTalla(prev => prev === t ? null : t);
  const toggleFiltroEstado = (e) => setFiltroEstado(prev => prev === e ? null : e);

  return (
    <div className="min-h-screen bg-[#F7F5F0] text-[#2C241B] relative pb-20">

      {/* MODAL LOGIN */}
      {mostrarAuth && (
        <Auth
          onCerrar={() => setMostrarAuth(false)}
          onLogin={(user) => { setUsuario(user); setMostrarAuth(false); }}
        />
      )}

      {/* MODAL CARRITO */}
      {mostrarCarrito && (
        <div className="fixed inset-0 bg-[#2C241B]/40 backdrop-blur-sm flex justify-end z-50">
          <div className="bg-[#F7F5F0] w-full max-w-md h-full shadow-2xl p-8 flex flex-col relative overflow-hidden">
            <button onClick={() => setMostrarCarrito(false)} className="absolute top-6 right-6 text-2xl hover:scale-110 transition-transform">✕</button>
            <h2 className="text-3xl font-serif italic mb-8 border-b border-[#2C241B]/20 pb-4">Su Selección</h2>
            <div className="flex-grow overflow-y-auto pr-4 flex flex-col gap-6">
              {carrito.length === 0 ? (
                <p className="text-stone-500 italic">No hay tesoros en su bolsa aún.</p>
              ) : (
                carrito.map((item, i) => (
                  <div key={i} className="flex justify-between items-center">
                    <div>
                      <span className="font-medium tracking-wide text-sm uppercase block">{item.nombre}</span>
                      {item.talla && <span className="text-xs text-stone-500">Talla {item.talla}</span>}
                    </div>
                    <span className="font-serif text-lg">{item.precio_unitario}€</span>
                  </div>
                ))
              )}
            </div>
            {carrito.length > 0 && (
              <div className="pt-6 border-t border-[#2C241B]/20 mt-6">
                <div className="flex justify-between items-center mb-6">
                  <span className="text-sm tracking-widest uppercase">Total</span>
                  <span className="text-3xl font-serif">{totalCarrito}€</span>
                </div>
                <button onClick={comprarCarrito} className="w-full bg-[#2C241B] text-[#F7F5F0] py-4 uppercase tracking-widest text-sm hover:bg-[#4A3F35] transition-colors">
                  Finalizar Compra
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* NAVBAR */}
      <header className="px-8 py-6 flex flex-col md:flex-row justify-between items-center border-b border-[#2C241B]/10 bg-[#F7F5F0] sticky top-0 z-40 shadow-sm">
        <h1 className="text-4xl font-serif italic tracking-wide text-[#2C241B] mb-4 md:mb-0">Retro&Street</h1>
        <div className="flex items-center gap-8 text-sm uppercase tracking-widest font-medium">
          {usuario ? (
            <div className="flex items-center gap-4">
              <span>M. {usuario.nombre}</span>
              <button onClick={cerrarSesion} className="text-red-800/80 hover:text-red-800 hover:underline">Salir</button>
            </div>
          ) : (
            <button onClick={() => setMostrarAuth(true)} className="hover:text-[#8B7355] transition-colors">Entrar / Registro</button>
          )}
          <button onClick={() => setMostrarCarrito(true)} className="flex items-center gap-2 hover:text-[#8B7355] transition-colors">
            Cesta ({carrito.length})
          </button>
        </div>
      </header>

      {/* PRODUCTO DESTACADO */}
      {!cargando && destacado && (
        <section className="max-w-[90rem] mx-auto px-8 py-16">
          <p className="uppercase tracking-[0.3em] text-[#8B7355] text-xs mb-6">Pieza de la semana</p>
          <div className="grid grid-cols-1 md:grid-cols-2 bg-[#EBE7E0]">
            <div className="aspect-[4/3] md:aspect-auto overflow-hidden">
              <img
                src={`${import.meta.env.VITE_API_URL}${destacado.url_imagen}`}
                alt={destacado.nombre}
                className="w-full h-full object-cover hover:scale-105 transition-transform duration-700"
              />
            </div>
            <div className="flex flex-col justify-center p-12">
              <span className="text-[10px] uppercase tracking-widest text-[#8B7355] mb-4">
                {destacado.estado} · Talla {destacado.talla}
              </span>
              <h2 className="text-4xl font-serif italic mb-4 text-[#2C241B]">{destacado.nombre}</h2>
              <p className="text-stone-500 font-light leading-relaxed mb-8">{destacado.descripcion}</p>
              <div className="flex items-center justify-between">
                <span className="text-3xl font-serif text-[#5C4A3D]">{destacado.precio_unitario}€</span>
                <button
                  onClick={() => añadirAlCarrito(destacado)}
                  className="bg-[#2C241B] text-[#F7F5F0] px-8 py-3 text-xs uppercase tracking-widest hover:bg-[#4A3F35] transition-colors"
                >
                  Añadir a la cesta
                </button>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* DROPS SEMANALES */}
      {!cargando && drops.length > 0 && (
        <section className="max-w-[90rem] mx-auto px-8 py-12 border-t border-[#2C241B]/10">
          <div className="flex items-baseline gap-4 mb-10">
            <h2 className="text-3xl font-serif italic text-[#2C241B]">Drops Semanales</h2>
            <span className="text-[10px] uppercase tracking-widest text-[#8B7355]">Nuevas llegadas</span>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-x-8 gap-y-16">
            {drops.map(art => (
              <ProductCard
                key={art.articulo_id}
                art={art}
                badge="Drop"
                esFav={favoritos.includes(art.articulo_id)}
                onFavorito={() => toggleFavorito(art.articulo_id)}
                onAnadir={() => añadirAlCarrito(art)}
              />
            ))}
          </div>
        </section>
      )}

      {/* HERO */}
      <div className="py-16 text-center px-4 max-w-3xl mx-auto border-t border-[#2C241B]/10">
        <p className="uppercase tracking-[0.3em] text-[#8B7355] text-xs mb-4">Colección 2026</p>
        <h2 className="text-5xl md:text-6xl font-serif italic mb-6 text-[#2C241B]">Prendas con historia.</h2>
        <p className="text-stone-600 font-light leading-relaxed">
          Cada pieza ha sido cuidadosamente seleccionada para garantizar autenticidad y carácter.
          Descubre la elegancia del streetwear atemporal.
        </p>
      </div>

      {/* FILTROS */}
      <div className="max-w-[90rem] mx-auto px-8 pb-10 flex flex-wrap gap-8 items-center">
        <div className="flex items-center gap-3">
          <span className="text-xs uppercase tracking-widest text-stone-400">Talla</span>
          {tallas.map(t => (
            <button
              key={t}
              onClick={() => toggleFiltroTalla(t)}
              className={`w-10 h-10 text-xs uppercase border transition-colors ${
                filtroTalla === t
                  ? 'bg-[#2C241B] text-[#F7F5F0] border-[#2C241B]'
                  : 'border-[#2C241B]/40 hover:border-[#2C241B] text-[#2C241B]'
              }`}
            >
              {t}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs uppercase tracking-widest text-stone-400">Estilo</span>
          {estados.map(e => (
            <button
              key={e}
              onClick={() => toggleFiltroEstado(e)}
              className={`px-4 py-2 text-xs uppercase tracking-widest border transition-colors ${
                filtroEstado === e
                  ? 'bg-[#2C241B] text-[#F7F5F0] border-[#2C241B]'
                  : 'border-[#2C241B]/40 hover:border-[#2C241B] text-[#2C241B]'
              }`}
            >
              {e}
            </button>
          ))}
        </div>
        {(filtroTalla || filtroEstado) && (
          <button
            onClick={() => { setFiltroTalla(null); setFiltroEstado(null); }}
            className="text-xs uppercase tracking-widest text-[#8B7355] underline"
          >
            Limpiar filtros
          </button>
        )}
      </div>

      {/* GRID CATÁLOGO */}
      {cargando ? (
        <div className="text-center py-20 font-serif text-xl italic text-stone-500 animate-pulse">
          Preparando el catálogo...
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-x-8 gap-y-16 max-w-[90rem] mx-auto px-8">
          {articulosFiltrados.length === 0 ? (
            <div className="col-span-4 text-center py-16 text-stone-500 italic font-serif">
              No hay prendas con esos filtros.
            </div>
          ) : (
            articulosFiltrados.map(art => (
              <ProductCard
                key={art.articulo_id}
                art={art}
                esFav={favoritos.includes(art.articulo_id)}
                onFavorito={() => toggleFavorito(art.articulo_id)}
                onAnadir={() => añadirAlCarrito(art)}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}

export default App;
