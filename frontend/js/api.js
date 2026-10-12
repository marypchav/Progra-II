// api.js: único lugar que habla con el servidor (backend/app.js)

const TEXTO_ALERTA = 'la suma de los porcentajes de sus beneficiarios no suma 100, favor corregir y cancelar la edición';

// hace la petición al servidor y devuelve la respuesta en JSON.
// credentials: 'same-origin' hace que viaje la cookie de sesión
async function http(metodo, url, cuerpo) {
  const opciones = { method: metodo, headers: {}, credentials: 'same-origin' };
  if (cuerpo !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(cuerpo);
  }
  const res = await fetch(url, opciones);
  return res.json();
}

// una función por cada ruta /api de app.js
const Api = {
  login: (u, p) => http('POST', '/api/login', { userName: u, pass: p }),
  logout: () => http('POST', '/api/logout'),
  sesion: () => http('GET', '/api/sesion'),
  catalogos: () => http('GET', '/api/catalogos'),
  beneficiarios: (idCuenta) => http('GET', `/api/cuentas/${idCuenta}/beneficiarios`),
  agregar: (idCuenta, d) => http('POST', `/api/cuentas/${idCuenta}/beneficiarios`, d),
  editar: (id, d) => http('PUT', `/api/beneficiarios/${id}`, d),
  eliminar: (id) => http('DELETE', `/api/beneficiarios/${id}`),
  estados: (idCuenta) => http('GET', `/api/cuentas/${idCuenta}/estados`)
};

// utilidades de formato (compartidas) 
// Las fechas llegan como '2000-05-20T00:00:00.000Z'. Se toman los primeros 10 caracteres para que se acomode mejor al formato
function fechaISO(texto) { return texto ? String(texto).slice(0, 10) : ''; }
function fechaLarga(texto) {
  const s = fechaISO(texto);
  if (!s) return '';
  const [a, m, d] = s.split('-');
  return `${d}/${m}/${a}`;
}
function dinero(valor, simbolo) {
  const n = Number(valor || 0);
  return (simbolo || '') + ' ' + n.toLocaleString('es-CR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function escapar(t) {
  return String(t ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}