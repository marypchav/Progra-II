// login.js: pantalla de ingreso
pintarIconos();

const form = $('formLogin');
const aviso = $('avisoLogin');

function mostrarAviso(texto, tipo) {
  const icos = { error: 'xcircle', ok: 'check', 'aviso-amarillo': 'alert' };
  aviso.className = 'aviso ' + tipo;
  aviso.innerHTML = icono(icos[tipo] || 'info') + `<span>${escapar(texto)}</span>`;
  aviso.hidden = false;
}

// mensajes que llegan desde otras pantallas (?m=salio / ?m=expirada)
const motivo = new URLSearchParams(location.search).get('m');
if (motivo === 'salio') mostrarAviso('Sesión cerrada correctamente. Ingrese de nuevo cuando lo necesite.', 'ok');
if (motivo === 'expirada') mostrarAviso('Su sesión terminó o aún no ha ingresado. Ingrese con su usuario y password.', 'aviso-amarillo');

// guía de usuarios de prueba (solo con datos simulados)
if (USAR_DATOS_SIMULADOS) $('demo').hidden = false;

$('verClave').addEventListener('click', () => {
  const oculto = $('pass').type === 'password';
  $('pass').type = oculto ? 'text' : 'password';
  $('verClave').textContent = oculto ? 'Ocultar' : 'Mostrar';
  $('verClave').setAttribute('aria-pressed', String(oculto));
});

$('btnLimpiar').addEventListener('click', () => {
  form.reset();
  $('cUsuario').classList.remove('con-error');
  $('cPass').classList.remove('con-error');
  aviso.hidden = true;
  $('usuario').focus();
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  aviso.hidden = true;
  const userName = $('usuario').value.trim();
  const pass = $('pass').value;

  $('cUsuario').classList.toggle('con-error', !userName);
  $('cPass').classList.toggle('con-error', !pass);
  if (!userName || !pass) { (userName ? $('pass') : $('usuario')).focus(); return; }

  const btn = $('btnIngresar');
  btn.disabled = true;
  btn.textContent = 'Ingresando...';
  try {
    const r = await Api.login(userName, pass);
    if (r.exito) {
      sessionStorage.removeItem('cuentaSel');
      window.location.href = 'inicio.html';
      return;
    }
    mostrarAviso(r.mensaje, 'error');
    $('pass').value = '';
    $('pass').focus();
  } catch (err) {
    mostrarAviso('No se pudo conectar con el servidor. Revise que esté encendido e intente de nuevo.', 'error');
  }
  btn.disabled = false;
  btn.textContent = 'Ingresar';
});