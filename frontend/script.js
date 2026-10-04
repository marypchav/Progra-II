// frontend/script.js
// Funciones que usará el frontend. Guardan la sesión y llaman a backend/server.js.
// Por ahora no hay sitio web: la prueba del final muestra todo en consola.
const servidor = require('../backend/server.js');

// IP del cliente. Cuando exista el sitio, el servidor debe leerla de la petición (req.ip)
// y pasarla aquí. Mientras tanto se usa un valor fijo.
const IP_CLIENTE = '127.0.0.1';

const TEXTO_ALERTA =
    'la suma de los porcentajes de sus beneficiarios no suma 100, favor corregir y cancelar la edición';

// ---------------- Estado de la sesión ----------------
const sesion = {
    usuario: null,           // { IdUsuario, UserName, EsAdministrador, IdPersona }
    cuentas: [],             // cuentas que el usuario puede ver
    cuentaSeleccionada: null // fila de la cuenta elegida
};

function haySesion() {
    return sesion.usuario !== null;
}

function exigirSesion() {
    if (!haySesion()) return { exito: false, mensaje: 'Debe iniciar sesión primero' };
    return null;
}

function exigirCuenta() {
    const e = exigirSesion();
    if (e) return e;
    if (!sesion.cuentaSeleccionada) return { exito: false, mensaje: 'Debe seleccionar una cuenta primero' };
    return null;
}

// ---------------- Login y logout ----------------
async function iniciarSesion(userName, pass) {
    if (!userName || !pass) {
        return { exito: false, mensaje: 'Debe ingresar usuario y password' };
    }
    const r = await servidor.login(userName.trim(), pass, IP_CLIENTE);
    if (r.exito) {
        sesion.usuario = r.usuario;
        sesion.cuentas = [];
        sesion.cuentaSeleccionada = null;
    }
    return { exito: r.exito, mensaje: r.mensaje, usuario: r.usuario };
}

async function cerrarSesion() {
    const e = exigirSesion();
    if (e) return e;
    const r = await servidor.logout(sesion.usuario.IdUsuario, IP_CLIENTE);
    if (r.exito) {
        sesion.usuario = null;
        sesion.cuentas = [];
        sesion.cuentaSeleccionada = null;
    }
    return { exito: r.exito, mensaje: r.exito ? 'Sesión cerrada' : r.mensaje };
}

// ---------------- Selección de cuenta ----------------
async function cargarCuentas() {
    const e = exigirSesion();
    if (e) return e;
    const r = await servidor.obtenerCuentasUsuario(sesion.usuario.IdUsuario);
    sesion.cuentas = r.datos;
    return { exito: true, mensaje: 'Cuentas cargadas', cuentas: r.datos };
}

// Se elige por IdCuenta, entre las cuentas que el usuario puede ver
function seleccionarCuenta(idCuenta) {
    const e = exigirSesion();
    if (e) return e;
    const cuenta = sesion.cuentas.find(c => c.IdCuenta === idCuenta);
    if (!cuenta) {
        return { exito: false, mensaje: 'La cuenta no está entre las que puede ver' };
    }
    sesion.cuentaSeleccionada = cuenta;
    return { exito: true, mensaje: 'Cuenta seleccionada', cuenta };
}

// ---------------- Beneficiarios ----------------
async function cargarCatalogosBeneficiario() {
    const e = exigirSesion();
    if (e) return e;
    const r = await servidor.obtenerCatalogosBeneficiario();
    return { exito: true, parentescos: r.parentescos, tiposDocumento: r.tiposDocumento };
}

async function cargarBeneficiarios() {
    const e = exigirCuenta();
    if (e) return e;
    const r = await servidor.listarBeneficiarios(sesion.usuario.IdUsuario, sesion.cuentaSeleccionada.IdCuenta);
    return { exito: r.exito, mensaje: r.mensaje, beneficiarios: r.datos };
}

// Devuelve { mostrarAlerta, mensaje } para que el frontend pinte la alerta llamativa
async function revisarAlertaPorcentajes() {
    const e = exigirCuenta();
    if (e) return e;
    const r = await servidor.alertaPorcentajes(sesion.usuario.IdUsuario, sesion.cuentaSeleccionada.IdCuenta);
    if (!r.exito) return { exito: false, mensaje: r.mensaje };
    return {
        exito: true,
        suma: r.suma,
        mostrarAlerta: r.mostrarAlerta,
        mensaje: r.mostrarAlerta ? TEXTO_ALERTA : ''
    };
}

// Validación previa en la capa lógica (el SP vuelve a validar)
function validarBeneficiario(d, esNuevo) {
    if (!d.nombre || d.nombre.trim() === '' || d.nombre.length > 64) return 'Nombre inválido (máximo 64 caracteres)';
    if (esNuevo && (!d.valorDocumento || !/^[0-9]{1,32}$/.test(d.valorDocumento))) return 'Documento inválido (solo números, máximo 32)';
    if (esNuevo && !d.idTipoDocuIdentidad) return 'Debe elegir un tipo de documento';
    if (!d.idParentesco) return 'Debe elegir un parentesco';
    const p = Number(d.porcentaje);
    if (!Number.isInteger(p) || p < 1 || p > 100) return 'El porcentaje debe ser un entero entre 1 y 100';
    if (!d.fechaNacimiento || isNaN(new Date(d.fechaNacimiento).getTime())) return 'Fecha de nacimiento inválida';
    if (!d.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email)) return 'Email inválido';
    if (!d.telefono1 || !/^[0-9]+$/.test(d.telefono1)) return 'Teléfono 1 inválido (solo números)';
    if (!d.telefono2 || !/^[0-9]+$/.test(d.telefono2)) return 'Teléfono 2 inválido (solo números)';
    return null;
}

async function agregarBeneficiario(datos) {
    const e = exigirCuenta();
    if (e) return e;
    const error = validarBeneficiario(datos, true);
    if (error) return { exito: false, mensaje: error };
    const r = await servidor.agregarBeneficiario(
        sesion.usuario.IdUsuario, sesion.cuentaSeleccionada.IdCuenta, IP_CLIENTE, datos);
    return { exito: r.exito, mensaje: r.mensaje };
}

async function editarBeneficiario(idBeneficiario, datos) {
    const e = exigirCuenta();
    if (e) return e;
    const error = validarBeneficiario(datos, false);
    if (error) return { exito: false, mensaje: error };
    const r = await servidor.actualizarBeneficiario(
        sesion.usuario.IdUsuario, idBeneficiario, IP_CLIENTE, datos);
    return { exito: r.exito, mensaje: r.mensaje };
}

async function eliminarBeneficiario(idBeneficiario) {
    const e = exigirCuenta();
    if (e) return e;
    const r = await servidor.eliminarBeneficiario(sesion.usuario.IdUsuario, idBeneficiario, IP_CLIENTE);
    return { exito: r.exito, mensaje: r.mensaje };
}

// ---------------- Estados de cuenta ----------------
async function cargarEstadosCuenta() {
    const e = exigirCuenta();
    if (e) return e;
    const r = await servidor.consultarEstadosCuenta(
        sesion.usuario.IdUsuario, sesion.cuentaSeleccionada.IdCuenta, IP_CLIENTE);
    return { exito: r.exito, mensaje: r.mensaje, estados: r.datos };
}

// ---------------- Prueba en consola ----------------
// Ejecutar con: node frontend/script.js
async function pruebaEnConsola() {
    try {
        console.log('--- Login con password incorrecto ---');
        console.log(await iniciarSesion('jaguero', 'incorrecta'));

        console.log('--- Login correcto ---');
        console.log(await iniciarSesion('jaguero', 'LaFacil'));

        console.log('--- Cuentas del usuario ---');
        const c = await cargarCuentas();
        console.table(c.cuentas);

        console.log('--- Seleccionar cuenta ---');
        const idCuenta = c.cuentas[0].IdCuenta;
        console.log(seleccionarCuenta(idCuenta));

        console.log('--- Catálogos del formulario ---');
        const cat = await cargarCatalogosBeneficiario();
        console.table(cat.parentescos);

        console.log('--- Beneficiarios ---');
        const b = await cargarBeneficiarios();
        console.table(b.beneficiarios);

        console.log('--- Alerta de porcentajes ---');
        console.log(await revisarAlertaPorcentajes());

        console.log('--- Agregar beneficiario (la cuenta 1 ya tiene 3, debe rechazar) ---');
        console.log(await agregarBeneficiario({
            idTipoDocuIdentidad: 1, valorDocumento: '999888777', nombre: 'Prueba Uno',
            fechaNacimiento: '1990-01-01', email: 'prueba@gmail.com',
            telefono1: '88887777', telefono2: '22223333', idParentesco: 7, porcentaje: 10
        }));

        console.log('--- Estados de cuenta (últimos 8) ---');
        const est = await cargarEstadosCuenta();
        console.table(est.estados);

        console.log('--- Intento de acceder a una cuenta ajena ---');
        console.log(seleccionarCuenta(3));

        console.log('--- Logout ---');
        console.log(await cerrarSesion());
    } catch (err) {
        console.error('Error en la prueba:', err.message);
    } finally {
        await servidor.cerrarConexion();
    }
}

// Solo corre la prueba si se ejecuta este archivo directamente
if (require.main === module) {
    pruebaEnConsola();
}

module.exports = {
    iniciarSesion,
    cerrarSesion,
    cargarCuentas,
    seleccionarCuenta,
    cargarCatalogosBeneficiario,
    cargarBeneficiarios,
    revisarAlertaPorcentajes,
    agregarBeneficiario,
    editarBeneficiario,
    eliminarBeneficiario,
    cargarEstadosCuenta,
    haySesion
};