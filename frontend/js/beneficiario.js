// beneficiario.js: formulario para insertar o editar un beneficiario (con validación de campos y alerta de suma)
(async () => {
  const ctx = await arrancar('beneficiarios', true);
  if (!ctx) return;
  const cuenta = ctx.cuenta;

  const idEditar = Number(new URLSearchParams(location.search).get('id')) || null;
  const esNuevo = idEditar === null;

  $('icoCab').innerHTML = icono(esNuevo ? 'userPlus' : 'userEdit');
  $('tituloForm').textContent = esNuevo ? 'Insertar beneficiario' : 'Editar beneficiario';
  $('migaActual').textContent = esNuevo ? 'Agregar' : 'Editar';
  document.title = (esNuevo ? 'Insertar' : 'Editar') + ' beneficiario | Mi Ahorro';
  $('notaDoc').hidden = !esNuevo;
  $('notaEditar').hidden = esNuevo;

  // ---- cargar catálogos y beneficiarios actuales ----
  let cat, r;
  try {
    [cat, r] = await Promise.all([Api.catalogos(), Api.beneficiarios(cuenta.IdCuenta)]);
  } catch (e) {
    $('cargandoForm').outerHTML = '<div id="errorForm"></div>';
    pintarError($('errorForm'), 'No hay conexión con el servidor. Revise que esté encendido.', () => location.reload());
    return;
  }
  if (!r.exito) {
    $('cargandoForm').outerHTML = '<div id="errorForm"></div>';
    pintarError($('errorForm'), r.mensaje, () => location.reload());
    return;
  }

  const lista = r.beneficiarios || [];
  const actual = esNuevo ? null : lista.find(b => b.IdBeneficiario === idEditar);

  if (!esNuevo && !actual) {
    $('cargandoForm').outerHTML = `<div class="estado-vacio error"><span class="estado-ico">${icono('xcircle')}</span>
      <h3>El beneficiario no existe</h3><p>Puede que ya haya sido eliminado.</p>
      <div class="estado-acc"><a class="btn primario" href="beneficiarios.html">Volver a beneficiarios</a></div></div>`;
    return;
  }
  if (esNuevo && lista.length >= 3) {
    flash('La cuenta ya tiene 3 beneficiarios activos. Elimine uno para poder agregar otro.', 'aviso');
    window.location.href = 'beneficiarios.html';
    return;
  }

  const otros = lista.filter(b => !actual || b.IdBeneficiario !== actual.IdBeneficiario);
  const sumaOtros = otros.reduce((s, b) => s + b.Porcentaje, 0);

  // ---- llenar selects ----
  function llenar(sel, items, campoId) {
    sel.innerHTML = '<option value="">Seleccione...</option>' +
      items.map(x => `<option value="${x[campoId]}">${escapar(x.Nombre)}</option>`).join('');
  }
  llenar($('fParentesco'), cat.parentescos || [], 'IdParentesco');
  llenar($('fTipoDoc'), cat.tiposDocumento || [], 'IdTipoDocuIdentidad');

  if (actual) {
    $('fNombre').value = actual.Nombre;
    $('fParentesco').value = actual.IdParentesco;
    $('fPorcentaje').value = actual.Porcentaje;
    $('fTipoDoc').value = actual.IdTipoDocuIdentidad;
    $('fDoc').value = actual.ValorDocumentoIdentidad;
    $('fFecha').value = fechaISO(actual.FechaNacimiento);
    $('fEmail').value = actual.Email;
    $('fTel1').value = actual.Telefono1;
    $('fTel2').value = actual.Telefono2;
    $('fTipoDoc').disabled = true;
    $('fDoc').disabled = true;
  }

  $('cargandoForm').hidden = true;
  $('formBenef').hidden = false;
  $('fNombre').focus();

  // ---- panel de suma en vivo ----
  function pintarSuma() {
    const mio = Number($('fPorcentaje').value) || 0;
    const total = sumaOtros + mio;
    const panel = $('panelSuma');
    panel.className = 'panel-suma ' + (total === 100 ? 'ok' : 'mal');
    $('sumaTotal').textContent = `${total}% de 100%`;
    $('sumaTotal').className = 'total ' + (total === 100 ? 'ok' : 'mal');

    const tramos = otros.map((b, i) =>
      `<div class="tramo k${i % 4}" style="width:${Math.min(b.Porcentaje, 100)}%" title="${escapar(b.Nombre)}: ${b.Porcentaje}%"></div>`);
    if (mio > 0) tramos.push(`<div class="tramo kyo" style="width:${Math.min(mio, 100)}%" title="Este beneficiario: ${mio}%"></div>`);
    $('barraSuma').className = 'barra-dist' + (total > 100 ? ' excede' : '');
    $('barraSuma').innerHTML = tramos.join('');

    let leyenda = otros.map((b, i) => `<span><i class="punto k${i % 4}"></i>${escapar(b.Nombre)} · ${b.Porcentaje}%</span>`).join('');
    leyenda += `<span><i class="punto kyo"></i>Este beneficiario · ${mio}%</span>`;
    if (total < 100) leyenda += `<span><i class="punto kotro"></i>Sin asignar · ${100 - total}%</span>`;
    if (total > 100) leyenda += `<span>Excede por ${total - 100}%</span>`;
    $('leyendaSuma').innerHTML = leyenda;

    $('alertaForm').hidden = total === 100;
    if (total !== 100) $('alertaFormTexto').textContent = TEXTO_ALERTA + ` (suma actual: ${total}%)`;
  }
  $('fPorcentaje').addEventListener('input', pintarSuma);
  pintarSuma();

  // ---- validación de campos (mismas reglas que la capa lógica y los SP) ----
  function datos() {
    return {
      nombre: $('fNombre').value.trim(),
      idParentesco: $('fParentesco').value,
      porcentaje: $('fPorcentaje').value.trim(),
      idTipoDocuIdentidad: $('fTipoDoc').value,
      valorDocumento: $('fDoc').value.trim(),
      fechaNacimiento: $('fFecha').value,
      email: $('fEmail').value.trim(),
      telefono1: $('fTel1').value.trim(),
      telefono2: $('fTel2').value.trim()
    };
  }

  // cada regla devuelve '' si está bien, o el mensaje de error
  const reglas = {
    cNombre: (d) => !d.nombre ? 'Ingrese el nombre.' : d.nombre.length > 64 ? 'El nombre no puede pasar de 64 caracteres.' : '',
    cParentesco: (d) => d.idParentesco ? '' : 'Elija un parentesco.',
    cPorcentaje: (d) => {
      const p = Number(d.porcentaje);
      if (d.porcentaje === '') return 'Ingrese el porcentaje.';
      if (!Number.isInteger(p)) return 'El porcentaje debe ser un número entero.';
      if (p < 1 || p > 100) return 'El porcentaje debe estar entre 1 y 100.';
      return '';
    },
    cTipoDoc: (d) => (esNuevo && !d.idTipoDocuIdentidad) ? 'Elija el tipo de documento.' : '',
    cDoc: (d) => !esNuevo ? '' : !d.valorDocumento ? 'Ingrese el número de documento.'
      : !/^[0-9]+$/.test(d.valorDocumento) ? 'Use solo números, sin guiones ni espacios.'
      : d.valorDocumento.length > 32 ? 'El documento no puede pasar de 32 dígitos.' : '',
    cFecha: (d) => {
      if (!d.fechaNacimiento) return 'Ingrese la fecha de nacimiento.';
      const hoy = new Date().toISOString().slice(0, 10);
      if (d.fechaNacimiento > hoy) return 'La fecha no puede ser futura.';
      if (d.fechaNacimiento < '1900-01-01') return 'La fecha no puede ser anterior a 1900.';
      return '';
    },
    cEmail: (d) => !d.email ? 'Ingrese el email.' : !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email) ? 'Escriba un email válido, por ejemplo nombre@correo.com.' : '',
    cTel1: (d) => !d.telefono1 ? 'Ingrese el teléfono 1.' : !/^[0-9]+$/.test(d.telefono1) ? 'Use solo números.' : '',
    cTel2: (d) => !d.telefono2 ? 'Ingrese el teléfono 2.' : !/^[0-9]+$/.test(d.telefono2) ? 'Use solo números.' : ''
  };
  const campoDe = { fNombre: 'cNombre', fParentesco: 'cParentesco', fPorcentaje: 'cPorcentaje', fTipoDoc: 'cTipoDoc', fDoc: 'cDoc', fFecha: 'cFecha', fEmail: 'cEmail', fTel1: 'cTel1', fTel2: 'cTel2' };

  function validarCampo(idContenedor) {
    const msg = reglas[idContenedor](datos());
    const cont = $(idContenedor);
    cont.classList.toggle('con-error', !!msg);
    cont.querySelector('.error-txt').textContent = msg;
    return msg;
  }

  Object.entries(campoDe).forEach(([idInput, idCont]) => {
    const el = $(idInput);
    el.addEventListener('blur', () => validarCampo(idCont));
    el.addEventListener('input', () => { if ($(idCont).classList.contains('con-error')) validarCampo(idCont); });
    el.addEventListener('change', () => { if ($(idCont).classList.contains('con-error')) validarCampo(idCont); });
  });
  // documento y teléfonos: solo dígitos
  ['fDoc', 'fTel1', 'fTel2'].forEach(id => $(id).addEventListener('input', (e) => {
    e.target.value = e.target.value.replace(/[^0-9]/g, '');
  }));

  function mostrarErrorForm(texto) {
    $('avisoForm').innerHTML = icono('xcircle') + `<span>${escapar(texto)}</span>`;
    $('avisoForm').hidden = false;
    $('avisoForm').scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  // ---- guardar ----
  $('formBenef').addEventListener('submit', async (e) => {
    e.preventDefault();
    $('avisoForm').hidden = true;

    const errores = Object.keys(reglas).filter(c => validarCampo(c));
    if (errores.length) {
      const primero = Object.entries(campoDe).find(([, c]) => c === errores[0]);
      if (primero) $(primero[0]).focus();
      mostrarErrorForm('Revise los campos marcados en rojo.');
      return;
    }

    const d = datos();
    const btn = $('btnGuardar');
    btn.disabled = true;
    btn.textContent = 'Guardando...';
    let res;
    try {
      res = esNuevo ? await Api.agregar(cuenta.IdCuenta, d) : await Api.editar(idEditar, d);
    } catch (err) {
      res = { exito: false, mensaje: 'No hay conexión con el servidor. Intente de nuevo.' };
    }

    if (res.exito) {
      const total = sumaOtros + Number(d.porcentaje);
      if (total !== 100) {
        flash(`${esNuevo ? 'Beneficiario agregado' : 'Cambios guardados'}, pero los porcentajes suman ${total}%. Corríjalos para llegar a 100%.`, 'aviso');
      } else {
        flash(esNuevo ? 'Beneficiario agregado.' : 'Cambios guardados.', 'ok');
      }
      window.location.href = 'beneficiarios.html';
      return;
    }

    btn.disabled = false;
    btn.textContent = 'Guardar';
    mostrarErrorForm(res.mensaje);
    // errores que impiden seguir: se muestran también como pantalla de alerta
    if (res.mensaje.includes('3 beneficiarios')) {
      await modal({ tipo: 'aviso', titulo: 'Límite de beneficiarios', mensaje: res.mensaje, textoOk: 'Volver a beneficiarios' });
      window.location.href = 'beneficiarios.html';
    }
  });

  // ---- regresar (con aviso si hay cambios sin guardar) ----
  const inicial = JSON.stringify(datos());
  $('btnRegresar').addEventListener('click', async () => {
    if (JSON.stringify(datos()) !== inicial) {
      const salir = await modal({
        tipo: 'aviso', titulo: 'Cambios sin guardar',
        mensaje: 'Si regresa ahora, perderá los datos que escribió.',
        textoOk: 'Salir sin guardar', textoCancelar: 'Seguir editando'
      });
      if (!salir) return;
    }
    window.location.href = 'beneficiarios.html';
  });
})();