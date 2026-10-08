// api.js: único lugar que habla con el servidor.
// Cambie USAR_DATOS_SIMULADOS a false cuando backend/app.js esté corriendo (http://localhost:3000).
const USAR_DATOS_SIMULADOS = false;

const TEXTO_ALERTA = 'la suma de los porcentajes de sus beneficiarios no suma 100, favor corregir y cancelar la edición';

// ---------- API real ----------
async function http(metodo, url, cuerpo) {
  const opciones = { method: metodo, headers: {}, credentials: 'same-origin' };
  if (cuerpo !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(cuerpo);
  }
  const res = await fetch(url, opciones);
  return res.json();
}

const ApiReal = {
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

// ---------- API simulada (datos en memoria por página; la sesión vive en sessionStorage) ----------
// Los beneficiarios se guardan en sessionStorage para que sobrevivan al cambiar de pantalla.
const SIM_USUARIOS = {
  jaguero: { pass: 'LaFacil', usuario: { IdUsuario: 1, UserName: 'jaguero', EsAdministrador: false, IdPersona: 1 }, cuentas: [1] },
  fquiros: { pass: 'MyPass123*', usuario: { IdUsuario: 2, UserName: 'fquiros', EsAdministrador: true, IdPersona: 3 }, cuentas: [1, 2, 3] }
};
const SIM_CUENTAS = [
  { IdCuenta: 1, NumeroCuenta: '11000001', NombreDueno: 'Javith Aguero Hernandez', TipoCuenta: 'Proletario', Simbolo: '₡', Saldo: 1000000, FechaCreacion: '2020-10-13T00:00:00.000Z' },
  { IdCuenta: 2, NumeroCuenta: '11000002', NombreDueno: 'Osvaldo Aguero Hernandez', TipoCuenta: 'Profesional', Simbolo: '₡', Saldo: 2350000.5, FechaCreacion: '2021-03-05T00:00:00.000Z' },
  { IdCuenta: 3, NumeroCuenta: '11000003', NombreDueno: 'Franco Quiros Ramirez', TipoCuenta: 'Exclusivo', Simbolo: '₡', Saldo: 5100000, FechaCreacion: '2022-07-21T00:00:00.000Z' }
];
const SIM_PARENTESCOS = [
  { IdParentesco: 7, Nombre: 'amigo' }, { IdParentesco: 8, Nombre: 'amiga' }, { IdParentesco: 6, Nombre: 'Hermana' },
  { IdParentesco: 5, Nombre: 'Hermano' }, { IdParentesco: 4, Nombre: 'Hija' }, { IdParentesco: 3, Nombre: 'Hijo' },
  { IdParentesco: 2, Nombre: 'Madre' }, { IdParentesco: 1, Nombre: 'Padre' }
];
const SIM_TIPOS_DOC = [
  { IdTipoDocuIdentidad: 1, Nombre: 'Cedula Nacional' }, { IdTipoDocuIdentidad: 2, Nombre: 'Cedula Residente' },
  { IdTipoDocuIdentidad: 3, Nombre: 'Pasaporte' }, { IdTipoDocuIdentidad: 4, Nombre: 'Cedula Juridica' },
  { IdTipoDocuIdentidad: 5, Nombre: 'Permiso de Trabajo' }, { IdTipoDocuIdentidad: 6, Nombre: 'Cedula Extranjera' }
];

function simBeneficiarioInicial(id, idCuenta, doc, nombre, idPar, pct, tel) {
  const par = SIM_PARENTESCOS.find(p => p.IdParentesco === idPar);
  return {
    IdBeneficiario: id, IdCuenta: idCuenta, IdTipoDocuIdentidad: 1, ValorDocumentoIdentidad: doc, Nombre: nombre,
    IdParentesco: idPar, Parentesco: par.Nombre, Porcentaje: pct, FechaNacimiento: '1994-10-13T00:00:00.000Z',
    Email: nombre.split(' ')[0].toLowerCase() + '@gmail.com', Telefono1: tel, Telefono2: '24197545'
  };
}

function simDatos() {
  const guardado = sessionStorage.getItem('simDatos');
  if (guardado) return JSON.parse(guardado);
  const d = {
    siguienteId: 10,
    beneficiarios: [
      // cuenta 1: suma 80 (dispara la alerta)
      simBeneficiarioInicial(1, 1, '12738545', 'Osvaldo Aguero Hernandez', 5, 50, '87541766'),
      simBeneficiarioInicial(2, 1, '130004000', 'Franco Quiros Ramirez', 7, 30, '87541767'),
      // cuenta 2: suma 100 (sin alerta), 3 beneficiarios (límite)
      simBeneficiarioInicial(3, 2, '117370445', 'Javith Aguero Hernandez', 5, 40, '85343403'),
      simBeneficiarioInicial(4, 2, '204560789', 'Maria Mora Solis', 2, 40, '88112233'),
      simBeneficiarioInicial(5, 2, '305670890', 'Lucia Mora Solis', 6, 20, '88112244')
      // cuenta 3: sin beneficiarios (suma 0, dispara la alerta)
    ]
  };
  sessionStorage.setItem('simDatos', JSON.stringify(d));
  return d;
}
const simGuardar = (d) => sessionStorage.setItem('simDatos', JSON.stringify(d));

const pausa = () => new Promise(r => setTimeout(r, 150));
const ok = (extra = {}) => ({ exito: true, mensaje: 'Operación exitosa', ...extra });
const fallo = (mensaje) => ({ exito: false, mensaje });

function simUsuarioActual() {
  const u = sessionStorage.getItem('simUser');
  return u ? SIM_USUARIOS[u] : null;
}
function simCuentasDe(u) {
  return u.usuario.EsAdministrador ? SIM_CUENTAS : SIM_CUENTAS.filter(c => u.cuentas.includes(c.IdCuenta));
}
function simTieneAcceso(u, idCuenta) { return simCuentasDe(u).some(c => c.IdCuenta === Number(idCuenta)); }
function simAlerta(d, idCuenta) {
  const suma = d.beneficiarios.filter(b => b.IdCuenta === Number(idCuenta)).reduce((s, b) => s + b.Porcentaje, 0);
  return { suma, mostrarAlerta: suma !== 100 };
}
function simEstados(idCuenta) {
  const base = SIM_CUENTAS.find(c => c.IdCuenta === Number(idCuenta)).Saldo;
  return Array.from({ length: 8 }, (_, i) => {
    const fecha = (m) => new Date(Date.UTC(2026, m - 1, 12)).toISOString();
    const mes = 10 - i;
    return {
      IdEstadoCuenta: 8 - i, FechaInicio: fecha(mes - 1), FechaFin: fecha(mes), FechaEmision: fecha(mes),
      SaldoInicial: base - (i + 1) * 12000, SaldoFinal: base - i * 12000, SaldoMinimo: base - (i + 1) * 15000,
      InteresesAcumulados: i === 3 ? null : 1500 + i * 40, CantRetiros: i % 3, CantDepositos: 2 + (i % 2),
      CantSinpeEntrantes: 1 + (i % 2), CantSinpeSalientes: i % 2
    };
  });
}

const ApiSimulada = {
  async login(u, p) {
    await pausa();
    const reg = SIM_USUARIOS[u];
    if (reg && reg.pass === p) {
      sessionStorage.setItem('simUser', u);
      return ok({ usuario: reg.usuario, cuentas: simCuentasDe(reg) });
    }
    return fallo('Usuario o password incorrectos');
  },
  async logout() { await pausa(); sessionStorage.removeItem('simUser'); return ok(); },
  async sesion() {
    await pausa();
    const u = simUsuarioActual();
    return u ? ok({ usuario: u.usuario, cuentas: simCuentasDe(u) }) : fallo('Debe iniciar sesión primero');
  },
  async catalogos() { await pausa(); return ok({ parentescos: SIM_PARENTESCOS, tiposDocumento: SIM_TIPOS_DOC }); },
  async beneficiarios(idCuenta) {
    await pausa();
    const u = simUsuarioActual();
    if (!u || !simTieneAcceso(u, idCuenta)) return fallo('El usuario no tiene acceso a esa cuenta');
    const d = simDatos();
    return ok({ beneficiarios: d.beneficiarios.filter(b => b.IdCuenta === Number(idCuenta)), alerta: simAlerta(d, idCuenta) });
  },
  async agregar(idCuenta, x) {
    await pausa();
    const u = simUsuarioActual();
    if (!u || !simTieneAcceso(u, idCuenta)) return fallo('El usuario no tiene acceso a esa cuenta');
    const d = simDatos();
    const activos = d.beneficiarios.filter(b => b.IdCuenta === Number(idCuenta));
    if (activos.length >= 3) return fallo('La cuenta ya tiene 3 beneficiarios activos');
    if (activos.some(b => b.ValorDocumentoIdentidad === x.valorDocumento)) return fallo('Esa persona ya es beneficiario activo de la cuenta');
    const par = SIM_PARENTESCOS.find(p => p.IdParentesco === Number(x.idParentesco));
    d.beneficiarios.push({
      IdBeneficiario: d.siguienteId++, IdCuenta: Number(idCuenta), IdTipoDocuIdentidad: Number(x.idTipoDocuIdentidad),
      ValorDocumentoIdentidad: x.valorDocumento, Nombre: x.nombre, IdParentesco: Number(x.idParentesco), Parentesco: par ? par.Nombre : '',
      Porcentaje: Number(x.porcentaje), FechaNacimiento: x.fechaNacimiento + 'T00:00:00.000Z', Email: x.email,
      Telefono1: x.telefono1, Telefono2: x.telefono2
    });
    simGuardar(d);
    return ok();
  },
  async editar(id, x) {
    await pausa();
    const d = simDatos();
    const b = d.beneficiarios.find(y => y.IdBeneficiario === Number(id));
    if (!b) return fallo('El beneficiario no existe o ya fue eliminado');
    const u = simUsuarioActual();
    if (!u || !simTieneAcceso(u, b.IdCuenta)) return fallo('El usuario no tiene acceso a esa cuenta');
    const par = SIM_PARENTESCOS.find(p => p.IdParentesco === Number(x.idParentesco));
    Object.assign(b, {
      Nombre: x.nombre, IdParentesco: Number(x.idParentesco), Parentesco: par ? par.Nombre : '', Porcentaje: Number(x.porcentaje),
      FechaNacimiento: x.fechaNacimiento + 'T00:00:00.000Z', Email: x.email, Telefono1: x.telefono1, Telefono2: x.telefono2
    });
    simGuardar(d);
    return ok();
  },
  async eliminar(id) {
    await pausa();
    const d = simDatos();
    const i = d.beneficiarios.findIndex(y => y.IdBeneficiario === Number(id));
    if (i < 0) return fallo('El beneficiario no existe o ya fue eliminado');
    const u = simUsuarioActual();
    if (!u || !simTieneAcceso(u, d.beneficiarios[i].IdCuenta)) return fallo('El usuario no tiene acceso a esa cuenta');
    d.beneficiarios.splice(i, 1);
    simGuardar(d);
    return ok();
  },
  async estados(idCuenta) {
    await pausa();
    const u = simUsuarioActual();
    if (!u || !simTieneAcceso(u, idCuenta)) return fallo('El usuario no tiene acceso a esa cuenta');
    return ok({ estados: simEstados(idCuenta) });
  }
};

const Api = USAR_DATOS_SIMULADOS ? ApiSimulada : ApiReal;

// ---------- utilidades de formato (compartidas) ----------
// Las fechas llegan como '2000-05-20T00:00:00.000Z'. Se toman los primeros 10 caracteres para evitar el desfase de zona horaria.
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