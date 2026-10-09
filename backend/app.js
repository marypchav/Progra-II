// backend/app.js: servidor web (Express). Es el puente entre el navegador y backend/server.js.
//  - sirve los archivos de /frontend (html, css, js)
//  - expone la API (/api/...) que usa frontend/js/api.js (ApiReal)
//  - guarda la sesión en el servidor: el navegador solo recibe una cookie
require('dotenv').config();
const path = require('path');
const express = require('express');
const session = require('express-session');
const db = require('./server.js'); // único archivo que habla con SQL Server

const app = express();
const PUERTO = process.env.PORT || 3000;

app.use(express.json()); // para leer el JSON que manda api.js en POST y PUT

app.use(session({
    secret: process.env.SESSION_SECRET || 'cambie-esto-en-el-env',
    resave: false,
    saveUninitialized: false, // no crea cookie hasta que haya login
    cookie: { httpOnly: true, sameSite: 'lax', maxAge: 30 * 60 * 1000 } // 30 min
}));

// el frontend se sirve desde el mismo servidor, así que no hay problemas de CORS
// y la cookie de sesión viaja sola (api.js usa credentials: 'same-origin')
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// ---------- utilidades ----------

const fallo = (mensaje) => ({ exito: false, mensaje });

// ip del cliente para la bitácora
const ipDe = (req) => ((req.ip || '').replace('::ffff:', '') || '127.0.0.1');

// convierte un parámetro de la URL en entero positivo (o null si no sirve)
function idDe(valor) {
    const n = Number(valor);
    return Number.isInteger(n) && n > 0 ? n : null;
}

// entero o null. si llega algo raro, el SP responde con su código de error
function entero(v) {
    if (v === null || v === undefined || v === '') return null;
    const n = Number(v);
    return Number.isInteger(n) ? n : null;
}

const texto = (v) => (v === null || v === undefined ? '' : String(v));

// arma el objeto que esperan agregarBeneficiario / actualizarBeneficiario de server.js
function datosBeneficiario(b = {}) {
    return {
        idTipoDocuIdentidad: entero(b.idTipoDocuIdentidad),
        valorDocumento: texto(b.valorDocumento),
        nombre: texto(b.nombre),
        fechaNacimiento: b.fechaNacimiento,
        email: texto(b.email),
        telefono1: texto(b.telefono1),
        telefono2: texto(b.telefono2),
        idParentesco: entero(b.idParentesco),
        porcentaje: entero(b.porcentaje)
    };
}

// middleware: corta la petición si no hay sesión
function exigirSesion(req, res, next) {
    if (!req.session.usuario) return res.status(401).json(fallo('Debe iniciar sesión primero'));
    next();
}

// atrapa errores de las funciones async (ej. se cayó la conexión a SQL Server)
const ruta = (fn) => (req, res) =>
    fn(req, res).catch((err) => {
        console.error(err);
        res.status(500).json(fallo('Error en el servidor. Revise la consola del backend.'));
    });

// ---------- sesión ----------

app.post('/api/login', ruta(async (req, res) => {
    const { userName, pass } = req.body || {};
    if (!userName || !pass) return res.json(fallo('Debe ingresar usuario y password'));

    const r = await db.login(String(userName).trim(), String(pass), ipDe(req));
    if (!r.exito) return res.json(fallo(r.mensaje));

    const c = await db.obtenerCuentasUsuario(r.usuario.IdUsuario);
    req.session.usuario = r.usuario; // desde aquí el servidor sabe quién es
    res.json({ exito: true, mensaje: r.mensaje, usuario: r.usuario, cuentas: c.datos });
}));

app.post('/api/logout', ruta(async (req, res) => {
    if (req.session.usuario) {
        await db.logout(req.session.usuario.IdUsuario, ipDe(req)); // queda en bitácora
    }
    req.session.destroy(() => {
        res.clearCookie('connect.sid');
        res.json({ exito: true, mensaje: 'Sesión cerrada' });
    });
}));

// el frontend lo usa al cargar cada página para saber si hay sesión activa
app.get('/api/sesion', exigirSesion, ruta(async (req, res) => {
    const c = await db.obtenerCuentasUsuario(req.session.usuario.IdUsuario);
    res.json({ exito: true, mensaje: 'Sesión activa', usuario: req.session.usuario, cuentas: c.datos });
}));

// ---------- catálogos ----------

app.get('/api/catalogos', exigirSesion, ruta(async (req, res) => {
    const r = await db.obtenerCatalogosBeneficiario();
    res.json({ exito: true, mensaje: r.mensaje, parentescos: r.parentescos, tiposDocumento: r.tiposDocumento });
}));

// ---------- beneficiarios ----------
// OJO: el IdUsuario sale SIEMPRE de la sesión, nunca del cuerpo de la petición.
// Si saliera del navegador, cualquiera podría hacerse pasar por otro usuario.

app.get('/api/cuentas/:idCuenta/beneficiarios', exigirSesion, ruta(async (req, res) => {
    const idCuenta = idDe(req.params.idCuenta);
    if (!idCuenta) return res.json(fallo('Cuenta inválida'));
    const idUsuario = req.session.usuario.IdUsuario;

    const lista = await db.listarBeneficiarios(idUsuario, idCuenta);
    if (!lista.exito) return res.json(fallo(lista.mensaje));

    const a = await db.alertaPorcentajes(idUsuario, idCuenta);
    if (!a.exito) return res.json(fallo(a.mensaje));

    res.json({
        exito: true,
        mensaje: lista.mensaje,
        beneficiarios: lista.datos,
        alerta: { suma: a.suma, mostrarAlerta: a.mostrarAlerta }
    });
}));

app.post('/api/cuentas/:idCuenta/beneficiarios', exigirSesion, ruta(async (req, res) => {
    const idCuenta = idDe(req.params.idCuenta);
    if (!idCuenta) return res.json(fallo('Cuenta inválida'));
    const r = await db.agregarBeneficiario(
        req.session.usuario.IdUsuario, idCuenta, ipDe(req), datosBeneficiario(req.body));
    res.json({ exito: r.exito, mensaje: r.mensaje });
}));

app.put('/api/beneficiarios/:id', exigirSesion, ruta(async (req, res) => {
    const id = idDe(req.params.id);
    if (!id) return res.json(fallo('Beneficiario inválido'));
    const r = await db.actualizarBeneficiario(
        req.session.usuario.IdUsuario, id, ipDe(req), datosBeneficiario(req.body));
    res.json({ exito: r.exito, mensaje: r.mensaje });
}));

app.delete('/api/beneficiarios/:id', exigirSesion, ruta(async (req, res) => {
    const id = idDe(req.params.id);
    if (!id) return res.json(fallo('Beneficiario inválido'));
    const r = await db.eliminarBeneficiario(req.session.usuario.IdUsuario, id, ipDe(req));
    res.json({ exito: r.exito, mensaje: r.mensaje });
}));

// ---------- estados de cuenta ----------

app.get('/api/cuentas/:idCuenta/estados', exigirSesion, ruta(async (req, res) => {
    const idCuenta = idDe(req.params.idCuenta);
    if (!idCuenta) return res.json(fallo('Cuenta inválida'));
    const r = await db.consultarEstadosCuenta(req.session.usuario.IdUsuario, idCuenta, ipDe(req));
    res.json({ exito: r.exito, mensaje: r.mensaje, estados: r.datos });
}));

// cualquier otra ruta /api responde JSON (y no una página html de error)
app.use('/api', (req, res) => res.status(404).json(fallo('Ruta no encontrada')));

// ---------- arranque ----------

app.listen(PUERTO, () => {
    console.log(`Servidor listo en http://localhost:${PUERTO}`);
});

// al cerrar con Ctrl+C se libera la conexión a SQL Server
process.on('SIGINT', async () => {
    await db.cerrarConexion();
    process.exit(0);
});