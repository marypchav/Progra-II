// comun.js: funciones compartidas por todas las pantallas. Se carga DESPUÉS de api.js.
// api.js ya define: Api, escapar, dinero, fechaLarga, fechaISO y TEXTO_ALERTA (no se repiten aquí).

const $ = (id) => document.getElementById(id);

// ---------- iconos (estilo línea, 24x24) ----------
// cada valor es el contenido interno del <svg>; icono() lo envuelve
const ICONOS = {
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  lock: '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  card: '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/>',
  search: '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
  alert: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
  check: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
  xcircle: '<circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>',
  info: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
  users: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>',
  home: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
  plus: '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  edit: '<path d="M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/>',
  trash: '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
  x: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'
};

// devuelve el <svg> como texto, para meterlo en un innerHTML
function icono(nombre) {
  const interior = ICONOS[nombre] || ICONOS.info;
  return '<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + interior + '</svg>';
}

// rellena todos los elementos que traen data-ico="nombre" en el HTML
function pintarIconos(raiz) {
  (raiz || document).querySelectorAll('[data-ico]').forEach((el) => {
    el.innerHTML = icono(el.dataset.ico);
  });
}

// ---------- utilidades ----------
function esAdmin(usuario) {
  return !!usuario && (usuario.EsAdministrador === true || usuario.EsAdministrador === 1);
}

function iniciales(texto) {
  const partes = String(texto || '').trim().split(/\s+/).filter(Boolean);
  if (!partes.length) return '?';
  const a = partes[0][0];
  const b = partes[1] ? partes[1][0] : (partes[0][1] || '');
  return (a + b).toUpperCase();
}

// ---------- cuenta elegida ----------
// la sesión real vive en el servidor (cookie). Aquí solo se recuerda qué cuenta eligió el usuario.
const CLAVE_CUENTA = 'cuentaSel';

function elegirCuenta(idCuenta) {
  sessionStorage.setItem(CLAVE_CUENTA, String(idCuenta));
}

// devuelve el IdCuenta como número (o null si no hay ninguna elegida)
function cuentaGuardada() {
  const n = Number(sessionStorage.getItem(CLAVE_CUENTA));
  return Number.isInteger(n) && n > 0 ? n : null;
}

// ---------- mensaje que sobrevive a un cambio de pantalla ----------
function flash(texto, tipo) {
  sessionStorage.setItem('flash', JSON.stringify({ texto, tipo: tipo || 'ok' }));
}

function mostrarFlash() {
  const f = sessionStorage.getItem('flash');
  if (!f) return;
  sessionStorage.removeItem('flash');
  const { texto, tipo } = JSON.parse(f);
  toast(texto, tipo);
}

// ---------- avisos y confirmaciones ----------
// mensaje flotante abajo a la derecha. tipo: 'ok' | 'error' | 'aviso'
function toast(texto, tipo) {
  tipo = tipo || 'ok';
  let caja = $('toasts');
  if (!caja) {
    caja = document.createElement('div');
    caja.id = 'toasts';
    caja.className = 'toasts';
    caja.setAttribute('role', 'status');
    caja.setAttribute('aria-live', 'polite');
    document.body.appendChild(caja);
  }
  const icos = { ok: 'check', error: 'xcircle', aviso: 'alert' };
  const t = document.createElement('div');
  t.className = 'toast ' + tipo;
  t.innerHTML = icono(icos[tipo] || 'info') + `<span>${escapar(texto)}</span>`;
  caja.appendChild(t);
  setTimeout(() => {
    t.classList.add('sale');
    setTimeout(() => t.remove(), 300);
  }, 4000);
}

// ventana de confirmación. devuelve una promesa: true si aceptó, false si canceló o cerró con Esc
// opciones: { titulo, mensaje, detalle, textoAceptar, textoCancelar, peligro, tipo: 'aviso' }
function confirmar(opc) {
  const o = Object.assign({
    titulo: 'Confirmar', mensaje: '', detalle: '', textoAceptar: 'Aceptar',
    textoCancelar: 'Cancelar', peligro: false, tipo: ''
  }, opc);
  const claseCab = o.peligro ? 'peligro' : o.tipo;
  return new Promise((resolver) => {
    const d = document.createElement('dialog');
    d.className = 'modal';
    d.innerHTML = `
      <div class="modal-cab ${claseCab}">
        <span class="modal-ico">${icono(o.peligro || o.tipo === 'aviso' ? 'alert' : 'info')}</span>
        <h3>${escapar(o.titulo)}</h3>
      </div>
      <div class="modal-cuerpo">
        <p>${escapar(o.mensaje)}</p>
        ${o.detalle ? `<p class="modal-detalle">${escapar(o.detalle)}</p>` : ''}
      </div>
      <div class="modal-pie">
        <button type="button" class="btn secundario" data-r="0">${escapar(o.textoCancelar)}</button>
        <button type="button" class="btn ${o.peligro ? 'peligro-fuerte' : 'primario'}" data-r="1">${escapar(o.textoAceptar)}</button>
      </div>`;
    document.body.appendChild(d);
    let acepto = false;
    d.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-r]');
      if (b) { acepto = b.dataset.r === '1'; d.close(); }
    });
    d.addEventListener('close', () => { d.remove(); resolver(acepto); });
    d.showModal();
  });
}

// ---------- cerrar sesión ----------
async function salir() {
  const si = await confirmar({
    tipo: 'aviso', titulo: 'Cerrar sesión', mensaje: '¿Desea cerrar su sesión?',
    textoAceptar: 'Cerrar sesión', textoCancelar: 'Quedarme'
  });
  if (!si) return;
  try { await Api.logout(); } catch (e) { /* aunque falle el servidor, se sale de la pantalla */ }
  sessionStorage.removeItem(CLAVE_CUENTA);
  window.location.href = 'index.html?m=salio';
}

// ---------- barra de navegación y contexto de cuenta ----------
function pintarNavbar(pagina, usuario) {
  const nav = $('navbar');
  if (!nav) return;
  const admin = esAdmin(usuario);
  const enlace = (id, href, ico, texto) =>
    `<a class="nav-link${pagina === id ? ' activo' : ''}" href="${href}" ${pagina === id ? 'aria-current="page"' : ''}>${icono(ico)}<span>${texto}</span></a>`;
  nav.innerHTML = `
    <div class="nav-in">
      <a class="marca" href="inicio.html"><span class="marca-logo">${icono('shield')}</span><span>Mi Ahorro</span></a>
      <nav class="nav-links" aria-label="Secciones">
        ${enlace('inicio', 'inicio.html', 'home', 'Inicio')}
        ${enlace('beneficiarios', 'beneficiarios.html', 'users', 'Beneficiarios')}
        ${enlace('estados', 'estados.html', 'file', 'Estados de cuenta')}
      </nav>
      <div class="nav-user">
        <span class="rol ${admin ? 'admin' : 'cliente'}">${admin ? 'Administrador' : 'Cliente'}</span>
        <span class="avatar" aria-hidden="true">${escapar(iniciales(usuario.UserName))}</span>
        <span class="nav-nombre">${escapar(usuario.UserName)}</span>
        <button id="btnSalir" class="btn-salir" type="button" title="Cerrar sesión">${icono('logout')}<span>Salir</span></button>
      </div>
    </div>`;
  $('btnSalir').addEventListener('click', salir);
}

// franja con la cuenta elegida, justo debajo de la barra (solo en pantallas que necesitan cuenta)
function pintarContexto(cuenta) {
  const nav = $('navbar');
  if (!nav) return;
  const previa = document.querySelector('.ctx');
  if (previa) previa.remove();
  const ctx = document.createElement('div');
  ctx.className = 'ctx';
  ctx.innerHTML = `
    <div class="ctx-in">
      <span class="ctx-ico">${icono('card')}</span>
      <div class="ctx-datos">
        <strong>Cuenta ${escapar(cuenta.NumeroCuenta)}</strong>
        <span>${escapar(cuenta.TipoCuenta)} · Dueño: ${escapar(cuenta.NombreDueno)}</span>
      </div>
      <div class="ctx-saldo"><span>Saldo</span><strong>${escapar(dinero(cuenta.Saldo, cuenta.Simbolo))}</strong></div>
      <a class="ctx-cambiar" href="inicio.html">Cambiar cuenta</a>
    </div>`;
  nav.insertAdjacentElement('afterend', ctx);
}

// ---------- arranque de cada pantalla ----------
// pagina: 'inicio' | 'beneficiarios' | 'estados' (resalta el enlace de la barra)
// requiereCuenta: true si la pantalla necesita una cuenta elegida (si no hay, vuelve a inicio)
// devuelve { usuario, cuentas, cuenta } o null si ya redirigió
async function arrancar(pagina, requiereCuenta) {
  pintarIconos();
  let r = null;
  try { r = await Api.sesion(); } catch (e) { r = null; }

  if (!r || !r.exito) {
    window.location.href = 'index.html?m=expirada';
    return null;
  }

  const usuario = r.usuario;
  const cuentas = r.cuentas || [];

  // si el usuario solo tiene una cuenta, se elige sola
  let cuenta = cuentas.find((c) => c.IdCuenta === cuentaGuardada()) || null;
  if (!cuenta && cuentas.length === 1) {
    cuenta = cuentas[0];
    elegirCuenta(cuenta.IdCuenta);
  }

  if (requiereCuenta && !cuenta) {
    flash('Elija primero una cuenta.', 'aviso');
    window.location.href = 'inicio.html';
    return null;
  }

  pintarNavbar(pagina, usuario);
  if (requiereCuenta) pintarContexto(cuenta);
  mostrarFlash();
  return { usuario, cuentas, cuenta };
}
