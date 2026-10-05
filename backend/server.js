// backend/server.js, unico archivo que habla con SQL Server. Todo se hace llamando procedimientos almacenados.
require('dotenv').config();
const sql = require('mssql');

// configuración de la conexión con el .env
const config = {
    server: process.env.DB_SERVER,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT ? parseInt(process.env.DB_PORT) : undefined,
    options: {
        encrypt: false,
        trustServerCertificate: true // evita errores de certificado en desarrollo
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
};

// nombres de los SP en un solo lugar
const SP = {
    LOGIN: 'spLogin',
    LOGOUT: 'spLogout',
    CUENTAS_USUARIO: 'spObtenerCuentasUsuario',
    CATALOGOS_BENEFICIARIO: 'spObtenerCatalogosBeneficiario',
    LISTAR_BENEFICIARIOS: 'spListarBeneficiarios',
    ALERTA_PORCENTAJES: 'spAlertaPorcentajes',
    AGREGAR_BENEFICIARIO: 'spAgregarBeneficiario',
    ACTUALIZAR_BENEFICIARIO: 'spActualizarBeneficiario',
    ELIMINAR_BENEFICIARIO: 'spEliminarBeneficiario',
    ESTADOS_CUENTA: 'spConsultarEstadosCuenta'
};

// mensajes para los códigos de error que devuelven los SP
const MENSAJES_ERROR = {
    0: 'Operación exitosa',
    50000: 'Error inesperado en la base de datos',
    50001: 'Usuario o password incorrectos',
    50002: 'El usuario no tiene acceso a esa cuenta',
    50003: 'La cuenta ya tiene 3 beneficiarios activos',
    50004: 'El nombre es inválido',
    50005: 'El documento de identidad es inválido (solo números)',
    50006: 'El porcentaje debe estar entre 1 y 100',
    50007: 'El parentesco no existe',
    50008: 'El tipo de documento no existe',
    50009: 'La fecha de nacimiento es inválida',
    50010: 'El email es inválido',
    50011: 'El teléfono es inválido (solo números)',
    50012: 'Esa persona ya es beneficiario activo de la cuenta',
    50013: 'El beneficiario no existe o ya fue eliminado',
    50014: 'La cuenta no existe'
};

// conexión con solo un pool para todo el programa, menos código
let pool = null;

async function obtenerPool() {
    if (!pool) {
        pool = await sql.connect(config);
    }
    return pool;
}

async function cerrarConexion() {
    if (pool) {
        await pool.close();
        pool = null;
    }
}

// función genérica para ejecutar un SP, entradas: [{ nombre, tipo, valor }]
async function ejecutarSP(nombreSP, entradas = [], conCodigo = true) {
    const p = await obtenerPool();
    const request = p.request();

    for (const e of entradas) {
        request.input(e.nombre, e.tipo, e.valor);
    }
    if (conCodigo) {
        request.output('OutResultCode', sql.Int);
    }

    const result = await request.execute(nombreSP);
    const codigo = conCodigo ? result.output.OutResultCode : 0;

    return {
        codigo,
        mensaje: MENSAJES_ERROR[codigo] || 'Código desconocido',
        exito: codigo === 0,
        datos: result.recordset || [], // primer resultado
        recordsets: result.recordsets || [] // todos los resultados
    };
}

// funciones por SP

async function login(userName, pass, ip) {
    const r = await ejecutarSP(SP.LOGIN, [
        { nombre: 'UserName', tipo: sql.VarChar(64), valor: userName },
        { nombre: 'Pass', tipo: sql.VarChar(64), valor: pass },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip }
    ]);
    // si el login sirve, el SP devuelve una fila con los datos del usuario
    r.usuario = r.exito ? r.datos[0] : null;
    return r;
}

async function logout(idUsuario, ip) {
    return ejecutarSP(SP.LOGOUT, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip }
    ]);
}

// este SP no tiene @OutResultCode
async function obtenerCuentasUsuario(idUsuario) {
    return ejecutarSP(SP.CUENTAS_USUARIO, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario }
    ], false);
}

// este SP devuelve 2 resultados: parentescos y tipos de documento
async function obtenerCatalogosBeneficiario() {
    const r = await ejecutarSP(SP.CATALOGOS_BENEFICIARIO, [], false);
    r.parentescos = r.recordsets[0] || [];
    r.tiposDocumento = r.recordsets[1] || [];
    return r;
}

async function listarBeneficiarios(idUsuario, idCuenta) {
    return ejecutarSP(SP.LISTAR_BENEFICIARIOS, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdCuenta', tipo: sql.Int, valor: idCuenta }
    ]);
}

async function alertaPorcentajes(idUsuario, idCuenta) {
    const r = await ejecutarSP(SP.ALERTA_PORCENTAJES, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdCuenta', tipo: sql.Int, valor: idCuenta }
    ]);
    if (r.exito && r.datos.length > 0) {
        r.suma = r.datos[0].SumaPorcentajes;
        r.mostrarAlerta = r.datos[0].MostrarAlerta === true || r.datos[0].MostrarAlerta === 1;
    }
    return r;
}

// d = { idTipoDocuIdentidad, valorDocumento, nombre, fechaNacimiento ('YYYY-MM-DD'), email, telefono1, telefono2, idParentesco, porcentaje }
async function agregarBeneficiario(idUsuario, idCuenta, ip, d) {
    return ejecutarSP(SP.AGREGAR_BENEFICIARIO, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdCuenta', tipo: sql.Int, valor: idCuenta },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip },
        { nombre: 'IdTipoDocuIdentidad', tipo: sql.Int, valor: d.idTipoDocuIdentidad },
        { nombre: 'ValorDocumento', tipo: sql.VarChar(32), valor: d.valorDocumento },
        { nombre: 'Nombre', tipo: sql.VarChar(64), valor: d.nombre },
        { nombre: 'FechaNacimiento', tipo: sql.Date, valor: convertirFecha(d.fechaNacimiento) },
        { nombre: 'Email', tipo: sql.VarChar(64), valor: d.email },
        { nombre: 'Telefono1', tipo: sql.VarChar(64), valor: d.telefono1 },
        { nombre: 'Telefono2', tipo: sql.VarChar(64), valor: d.telefono2 },
        { nombre: 'IdParentesco', tipo: sql.Int, valor: d.idParentesco },
        { nombre: 'Porcentaje', tipo: sql.Int, valor: d.porcentaje }
    ]);
}

// d = { nombre, fechaNacimiento, email, telefono1, telefono2, idParentesco, porcentaje }
// el tipo y valor del documento no se editan
async function actualizarBeneficiario(idUsuario, idBeneficiario, ip, d) {
    return ejecutarSP(SP.ACTUALIZAR_BENEFICIARIO, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdBeneficiario', tipo: sql.Int, valor: idBeneficiario },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip },
        { nombre: 'Nombre', tipo: sql.VarChar(64), valor: d.nombre },
        { nombre: 'FechaNacimiento', tipo: sql.Date, valor: convertirFecha(d.fechaNacimiento) },
        { nombre: 'Email', tipo: sql.VarChar(64), valor: d.email },
        { nombre: 'Telefono1', tipo: sql.VarChar(64), valor: d.telefono1 },
        { nombre: 'Telefono2', tipo: sql.VarChar(64), valor: d.telefono2 },
        { nombre: 'IdParentesco', tipo: sql.Int, valor: d.idParentesco },
        { nombre: 'Porcentaje', tipo: sql.Int, valor: d.porcentaje }
    ]);
}

async function eliminarBeneficiario(idUsuario, idBeneficiario, ip) {
    return ejecutarSP(SP.ELIMINAR_BENEFICIARIO, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdBeneficiario', tipo: sql.Int, valor: idBeneficiario },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip }
    ]);
}

async function consultarEstadosCuenta(idUsuario, idCuenta, ip) {
    return ejecutarSP(SP.ESTADOS_CUENTA, [
        { nombre: 'IdUsuario', tipo: sql.Int, valor: idUsuario },
        { nombre: 'IdCuenta', tipo: sql.Int, valor: idCuenta },
        { nombre: 'IP', tipo: sql.VarChar(64), valor: ip }
    ]);
}

function convertirFecha(texto) {
    if (!texto) return null;
    const f = new Date(texto);
    return isNaN(f.getTime()) ? null : f;
}

module.exports = {
    login,
    logout,
    obtenerCuentasUsuario,
    obtenerCatalogosBeneficiario,
    listarBeneficiarios,
    alertaPorcentajes,
    agregarBeneficiario,
    actualizarBeneficiario,
    eliminarBeneficiario,
    consultarEstadosCuenta,
    cerrarConexion
};