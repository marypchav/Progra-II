// beneficiarios.js: lista de beneficiarios, alerta de porcentajes, eliminar (lógico) y límite de 3
(async () => {
  const ctx = await arrancar('beneficiarios', true);
  if (!ctx) return;
  const cuenta = ctx.cuenta;
  let beneficiarios = [];
  let tiposDoc = [];

  async function cargar() {
    $('cuerpo').innerHTML = '<div class="cargando">Cargando beneficiarios...</div>';
    let cat, r;
    try {
      [cat, r] = await Promise.all([Api.catalogos(), Api.beneficiarios(cuenta.IdCuenta)]);
    } catch (e) {
      pintarError($('cuerpo'), 'No hay conexión con el servidor. Revise que esté encendido.', cargar);
      return;
    }
    if (!r.exito) { pintarError($('cuerpo'), r.mensaje, cargar); return; }
    tiposDoc = cat.tiposDocumento || [];
    beneficiarios = r.beneficiarios || [];
    pintarTodo(r.alerta);
  }

  function pintarAlerta(a) {
    if (a && a.mostrarAlerta) {
      $('textoAlerta').textContent = TEXTO_ALERTA;
      $('sumaActual').textContent = `Suma actual: ${a.suma}% de 100%`;
      $('alertaPorc').hidden = false;
    } else {
      $('alertaPorc').hidden = true;
    }
  }

  function nombreTipoDoc(id) {
    const t = tiposDoc.find(x => x.IdTipoDocuIdentidad === id);
    return t ? t.Nombre : '';
  }

  function pintarTodo(alerta) {
    pintarAlerta(alerta);
    const n = beneficiarios.length;
    $('subCab').textContent = `${n} de 3 beneficiarios activos`;

    const suma = alerta ? alerta.suma : beneficiarios.reduce((s, b) => s + b.Porcentaje, 0);
    const tramos = beneficiarios.map((b, i) =>
      `<div class="tramo k${i % 4}" style="width:${Math.min(b.Porcentaje, 100)}%" title="${escapar(b.Nombre)}: ${b.Porcentaje}%"></div>`).join('');
    let leyenda = beneficiarios.map((b, i) =>
      `<span><i class="punto k${i % 4}"></i>${escapar(b.Nombre)} · ${b.Porcentaje}%</span>`).join('');
    if (suma < 100) leyenda += `<span><i class="punto kotro"></i>Sin asignar · ${100 - suma}%</span>`;
    if (suma > 100) leyenda += `<span>Excede por ${suma - 100}%</span>`;

    const distribucion = `
      <div class="distribucion">
        <div class="distribucion-cab">
          <h3>Reparto del saldo entre beneficiarios</h3>
          <span class="total ${suma === 100 ? 'ok' : 'mal'}">${suma}% de 100%</span>
        </div>
        <div class="barra-dist ${suma > 100 ? 'excede' : ''}" role="img" aria-label="Porcentaje asignado: ${suma} por ciento">${tramos}</div>
        <div class="leyenda">${leyenda}</div>
      </div>`;

    if (n === 0) {
      $('cuerpo').innerHTML = distribucion + `
        <div class="estado-vacio"><span class="estado-ico">${icono('userPlus')}</span>
          <h3>Aún no tiene beneficiarios</h3>
          <p>Agregue hasta 3 personas para repartir su saldo entre ellas. La suma de sus porcentajes debe ser 100.</p>
          <div class="estado-acc"><button class="btn primario" id="btnAgregarVacio" type="button">Agregar beneficiario</button></div>
        </div>`;
      $('btnAgregarVacio').addEventListener('click', agregar);
      return;
    }

    $('cuerpo').innerHTML = distribucion + `
      <div class="tabla-wrap"><table>
        <thead><tr>
          <th>Beneficiario</th><th>Parentesco</th><th class="num">Porcentaje</th><th>Documento</th>
          <th>Nacimiento</th><th>Email</th><th>Teléfonos</th><th>Acciones</th>
        </tr></thead>
        <tbody>${beneficiarios.map((b, i) => `
          <tr>
            <td><div class="nombre-celda"><span class="avatar" aria-hidden="true">${escapar(iniciales(b.Nombre))}</span>
              <div><strong>${escapar(b.Nombre)}</strong></div></div></td>
            <td><span class="chip">${escapar(b.Parentesco)}</span></td>
            <td class="num"><span class="pct">${b.Porcentaje}%</span></td>
            <td><strong>${escapar(b.ValorDocumentoIdentidad)}</strong><br><small>${escapar(nombreTipoDoc(b.IdTipoDocuIdentidad))}</small></td>
            <td class="nowrap">${fechaLarga(b.FechaNacimiento)}</td>
            <td>${escapar(b.Email)}</td>
            <td class="nowrap">${escapar(b.Telefono1)}<br>${escapar(b.Telefono2)}</td>
            <td><div class="acciones">
              <button class="btn chico secundario" data-accion="editar" data-id="${b.IdBeneficiario}">${icono('edit')} Editar</button>
              <button class="btn chico peligro" data-accion="eliminar" data-id="${b.IdBeneficiario}">${icono('trash')} Eliminar</button>
            </div></td>
          </tr>`).join('')}</tbody></table></div>
      <p class="nota-pie">${icono('info')} Al eliminar un beneficiario queda inactivo (no se borra) y se guarda la fecha de desactivación.</p>`;
  }

  // ---- agregar: si ya hay 3, se muestra el aviso de límite ----
  async function agregar() {
    if (beneficiarios.length >= 3) {
      await modal({
        tipo: 'aviso', titulo: 'Límite de beneficiarios',
        mensaje: 'Una cuenta no puede tener más de 3 beneficiarios activos.',
        detalle: 'Elimine un beneficiario si desea agregar otro.', textoOk: 'Entendido'
      });
      return;
    }
    window.location.href = 'beneficiario.html';
  }
  $('btnAgregar').addEventListener('click', agregar);

  // ---- editar / eliminar ----
  $('cuerpo').addEventListener('click', async (e) => {
    const btn = e.target.closest('button[data-accion]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const b = beneficiarios.find(x => x.IdBeneficiario === id);
    if (!b) return;

    if (btn.dataset.accion === 'editar') {
      window.location.href = 'beneficiario.html?id=' + id;
      return;
    }

    const si = await modal({
      tipo: 'peligro', titulo: 'Eliminar beneficiario',
      mensaje: `¿Desea eliminar a ${b.Nombre} (${b.Porcentaje}%)?`,
      detalle: 'Quedará inactivo y su porcentaje dejará de contar. Si la suma deja de ser 100, se mostrará una alerta para que la corrija.',
      textoOk: 'Sí, eliminar', textoCancelar: 'Cancelar'
    });
    if (!si) return;

    btn.disabled = true;
    let r;
    try { r = await Api.eliminar(id); } catch (err) { r = { exito: false, mensaje: 'No hay conexión con el servidor.' }; }
    if (r.exito) {
      toast('Beneficiario eliminado.', 'ok');
      await cargar();
    } else {
      btn.disabled = false;
      await modal({ tipo: 'error', titulo: 'No se pudo eliminar', mensaje: r.mensaje, textoOk: 'Cerrar' });
      await cargar();
    }
  });

// beneficiarios.js: listar, agregar, editar y eliminar beneficiarios de la cuenta elegida.
(async () => {
  const ctx = await arrancar('beneficiarios', true);
  if (!ctx) return;
  const { cuenta } = ctx;
  const MAX = 3;

  const contenido = $('contenido');
  let lista = [];
  let cat = { parentescos: [], tiposDocumento: [] };

  // ---------- carga ----------
  async function cargar() {
    let r;
    try { r = await Api.beneficiarios(cuenta.IdCuenta); } catch (e) { r = null; }
    if (!r || !r.exito) {
      contenido.innerHTML = `<div class="estado-vacio error"><span class="estado-ico">${icono('xcircle')}</span>
        <h3>No se pudieron cargar los beneficiarios</h3><p>${escapar(r ? r.mensaje : 'No se pudo conectar con el servidor.')}</p>
        <div class="estado-acc"><button class="btn primario" onclick="location.reload()">Reintentar</button></div></div>`;
      return;
    }
    lista = r.beneficiarios || [];
    pintarAlerta(r.alerta);
    pintarDistribucion(r.alerta);
    pintarTabla();
    $('btnAgregar').disabled = lista.length >= MAX;
    $('btnAgregar').title = lista.length >= MAX ? 'Ya tiene 3 beneficiarios. Elimine uno para agregar otro.' : '';
  }

  // ---------- alerta (requisito: rótulo llamativo) ----------
  function pintarAlerta(a) {
    const mostrar = a && a.mostrarAlerta;
    $('alertaSuma').hidden = !mostrar;
    if (mostrar) {
      $('alertaTexto').textContent = TEXTO_ALERTA.charAt(0).toUpperCase() + TEXTO_ALERTA.slice(1) + '.';
      $('alertaNum').textContent = `Suma actual: ${a.suma}%`;
    }
  }

  // ---------- barra de distribución ----------
  function pintarDistribucion(a) {
    const suma = a ? a.suma : 0;
    if (!lista.length) { $('distribucion').innerHTML = ''; return; }
    const tramos = lista.map((b, i) =>
      `<div class="tramo k${Math.min(i, 3)}" style="width:${Math.min(b.Porcentaje, 100)}%" title="${escapar(b.Nombre)}: ${b.Porcentaje}%"></div>`).join('');
    const leyenda = lista.map((b, i) =>
      `<span><i class="punto k${Math.min(i, 3)}"></i>${escapar(b.Nombre)} (${b.Porcentaje}%)</span>`).join('');
    $('distribucion').innerHTML = `
      <div class="distribucion">
        <div class="distribucion-cab"><h3>Distribución del beneficio</h3>
          <span class="total ${suma === 100 ? 'ok' : 'mal'}">Total: ${suma}%</span></div>
        <div class="barra-dist ${suma > 100 ? 'excede' : ''}">${tramos}</div>
        <div class="leyenda">${leyenda}</div>
      </div>`;
  }

  // ---------- tabla ----------
  function pintarTabla() {
    if (!lista.length) {
      contenido.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('users')}</span>
        <h3>No tiene beneficiarios</h3><p>Agregue hasta 3 beneficiarios para esta cuenta.</p></div>`;
      return;
    }
    contenido.innerHTML = `<div class="tabla-wrap"><table>
      <thead><tr><th>Beneficiario</th><th>Documento</th><th>Parentesco</th><th class="num">Porcentaje</th>
        <th>Nacimiento</th><th>Contacto</th><th>Acciones</th></tr></thead>
      <tbody>${lista.map(b => {
        const tipo = (cat.tiposDocumento.find(t => t.IdTipoDocuIdentidad === b.IdTipoDocuIdentidad) || {}).Nombre || '';
        return `<tr>
          <td><div class="nombre-celda"><span class="avatar">${escapar(iniciales(b.Nombre))}</span>
            <div><strong>${escapar(b.Nombre)}</strong><small>${escapar(b.Email)}</small></div></div></td>
          <td class="nowrap">${escapar(b.ValorDocumentoIdentidad)}<br><small>${escapar(tipo)}</small></td>
          <td><span class="chip">${escapar(b.Parentesco)}</span></td>
          <td class="num"><span class="pct">${b.Porcentaje}%</span></td>
          <td class="nowrap">${fechaLarga(b.FechaNacimiento)}</td>
          <td class="nowrap">${escapar(b.Telefono1)}<br>${escapar(b.Telefono2)}</td>
          <td><div class="acciones">
            <button class="btn chico secundario" data-edit="${b.IdBeneficiario}">${icono('edit')} Editar</button>
            <button class="btn chico peligro" data-del="${b.IdBeneficiario}">${icono('trash')} Eliminar</button>
          </div></td></tr>`;
      }).join('')}</tbody></table></div>`;
  }

  contenido.addEventListener('click', (e) => {
    const ed = e.target.closest('button[data-edit]');
    const el = e.target.closest('button[data-del]');
    if (ed) abrirFormulario(lista.find(b => b.IdBeneficiario === Number(ed.dataset.edit)));
    if (el) eliminar(lista.find(b => b.IdBeneficiario === Number(el.dataset.del)));
  });
  $('btnAgregar').addEventListener('click', () => abrirFormulario(null));

  // ---------- eliminar ----------
  async function eliminar(b) {
    if (!b) return;
    const si = await confirmar({
      titulo: 'Eliminar beneficiario',
      mensaje: `¿Desea eliminar a ${b.Nombre}?`,
      detalle: 'Podrá agregar otro beneficiario en su lugar. Recuerde que los porcentajes restantes deben sumar 100.',
      textoAceptar: 'Eliminar', peligro: true
    });
    if (!si) return;
    const r = await Api.eliminar(b.IdBeneficiario);
    toast(r.exito ? 'Beneficiario eliminado' : r.mensaje, r.exito ? 'ok' : 'error');
    if (r.exito) cargar();
  }

  // ---------- formulario (agregar / editar) ----------
  function opciones(arr, idCampo, sel) {
    return arr.map(o => `<option value="${o[idCampo]}" ${o[idCampo] === sel ? 'selected' : ''}>${escapar(o.Nombre)}</option>`).join('');
  }

  function abrirFormulario(b) {
    const edita = !!b;
    const d = document.createElement('dialog');
    d.className = 'modal';
    d.style.width = 'min(640px, calc(100vw - 2rem))';
    d.innerHTML = `
      <div class="modal-cab"><span class="modal-ico">${icono(edita ? 'edit' : 'plus')}</span>
        <h3>${edita ? 'Editar beneficiario' : 'Agregar beneficiario'}</h3></div>
      <form class="modal-cuerpo" novalidate>
        <div id="formAviso" class="aviso error" role="alert" hidden></div>
        <div class="grid-2">
          <div class="campo"><label for="fTipo">Tipo de documento</label>
            <select id="fTipo" ${edita ? 'disabled' : ''}>
              <option value="">Seleccione...</option>${opciones(cat.tiposDocumento, 'IdTipoDocuIdentidad', b && b.IdTipoDocuIdentidad)}
            </select></div>
          <div class="campo"><label for="fDoc">Número de documento</label>
            <input id="fDoc" maxlength="32" inputmode="numeric" value="${edita ? escapar(b.ValorDocumentoIdentidad) : ''}" ${edita ? 'disabled' : ''}>
            ${edita ? '' : '<p class="ayuda">Solo números.</p>'}</div>
        </div>
        <div class="campo"><label for="fNombre">Nombre completo</label>
          <input id="fNombre" maxlength="64" value="${edita ? escapar(b.Nombre) : ''}"></div>
        <div class="grid-2">
          <div class="campo"><label for="fPar">Parentesco</label>
            <select id="fPar"><option value="">Seleccione...</option>${opciones(cat.parentescos, 'IdParentesco', b && b.IdParentesco)}</select></div>
          <div class="campo"><label for="fPct">Porcentaje (1 a 100)</label>
            <input id="fPct" type="number" min="1" max="100" step="1" value="${edita ? b.Porcentaje : ''}"></div>
        </div>
        <div class="grid-2">
          <div class="campo"><label for="fNac">Fecha de nacimiento</label>
            <input id="fNac" type="date" value="${edita ? fechaISO(b.FechaNacimiento) : ''}"></div>
          <div class="campo"><label for="fEmail">Email</label>
            <input id="fEmail" type="email" maxlength="64" value="${edita ? escapar(b.Email) : ''}"></div>
        </div>
        <div class="grid-2">
          <div class="campo"><label for="fTel1">Teléfono 1</label>
            <input id="fTel1" maxlength="64" inputmode="numeric" value="${edita ? escapar(b.Telefono1) : ''}"></div>
          <div class="campo"><label for="fTel2">Teléfono 2</label>
            <input id="fTel2" maxlength="64" inputmode="numeric" value="${edita ? escapar(b.Telefono2) : ''}"></div>
        </div>
        <div id="panelSuma" class="panel-suma"></div>
        <div class="modal-pie" style="padding:0">
          <button type="button" class="btn secundario" data-r="cancelar">Cancelar</button>
          <button type="submit" class="btn primario" id="fGuardar">${edita ? 'Guardar cambios' : 'Agregar'}</button>
        </div>
      </form>`;
    document.body.appendChild(d);
    const q = (id) => d.querySelector('#' + id);

    // suma de los OTROS beneficiarios + el porcentaje que se escribe
    const otros = lista.filter(x => !b || x.IdBeneficiario !== b.IdBeneficiario).reduce((s, x) => s + x.Porcentaje, 0);
    function actualizarSuma() {
      const nuevo = Number(q('fPct').value) || 0;
      const total = otros + nuevo;
      const p = q('panelSuma');
      p.className = 'panel-suma ' + (total === 100 ? 'ok' : 'mal');
      p.innerHTML = `<div class="panel-suma-cab"><span>Suma de porcentajes con este cambio</span>
        <span class="total ${total === 100 ? 'ok' : 'mal'}">${total}%</span></div>
        <p class="ayuda">${total === 100 ? 'La suma es correcta.'
          : total > 100 ? 'La suma supera 100. Ajuste este u otros beneficiarios.'
          : 'La suma no llega a 100. Puede guardar y ajustar los demás después, pero se mostrará la alerta.'}</p>`;
    }
    q('fPct').addEventListener('input', actualizarSuma);
    actualizarSuma();

    function error(texto) {
      const a = q('formAviso');
      a.innerHTML = icono('xcircle') + `<span>${escapar(texto)}</span>`;
      a.hidden = false;
    }

    d.addEventListener('click', (e) => {
      if (e.target.closest('[data-r="cancelar"]')) d.close();
    });
    d.addEventListener('close', () => d.remove());

    d.querySelector('form').addEventListener('submit', async (e) => {
      e.preventDefault();
      q('formAviso').hidden = true;
      const datos = {
        idTipoDocuIdentidad: q('fTipo').value ? Number(q('fTipo').value) : null,
        valorDocumento: q('fDoc').value.trim(),
        nombre: q('fNombre').value.trim(),
        idParentesco: q('fPar').value ? Number(q('fPar').value) : null,
        porcentaje: q('fPct').value,
        fechaNacimiento: q('fNac').value,
        email: q('fEmail').value.trim(),
        telefono1: q('fTel1').value.trim(),
        telefono2: q('fTel2').value.trim()
      };

      // validación en el navegador (el SP vuelve a validar todo)
      const msg = validar(datos, !edita);
      if (msg) return error(msg);

      const btn = q('fGuardar');
      btn.disabled = true;
      let r;
      try {
        r = edita ? await Api.editar(b.IdBeneficiario, datos) : await Api.agregar(cuenta.IdCuenta, datos);
      } catch (err) {
        r = { exito: false, mensaje: 'No se pudo conectar con el servidor.' };
      }
      btn.disabled = false;
      if (!r.exito) return error(r.mensaje);

      d.close();
      toast(edita ? 'Beneficiario actualizado' : 'Beneficiario agregado', 'ok');
      cargar();
    });

    d.showModal();
    (edita ? q('fNombre') : q('fTipo')).focus();
  }

  function validar(x, esNuevo) {
    if (!x.nombre || x.nombre.length > 64) return 'Ingrese un nombre válido (máximo 64 caracteres).';
    if (esNuevo && !x.idTipoDocuIdentidad) return 'Seleccione un tipo de documento.';
    if (esNuevo && !/^[0-9]{1,32}$/.test(x.valorDocumento)) return 'El documento debe contener solo números (máximo 32).';
    if (!x.idParentesco) return 'Seleccione un parentesco.';
    const p = Number(x.porcentaje);
    if (!Number.isInteger(p) || p < 1 || p > 100) return 'El porcentaje debe ser un entero entre 1 y 100.';
    if (!x.fechaNacimiento) return 'Ingrese la fecha de nacimiento.';
    if (new Date(x.fechaNacimiento) > new Date()) return 'La fecha de nacimiento no puede ser futura.';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x.email)) return 'Ingrese un email válido.';
    if (!/^[0-9]+$/.test(x.telefono1) || !/^[0-9]+$/.test(x.telefono2)) return 'Los dos teléfonos son obligatorios y solo con números.';
    return null;
  }

  // ---------- arranque ----------
  try {
    const c = await Api.catalogos();
    if (c.exito) cat = { parentescos: c.parentescos, tiposDocumento: c.tiposDocumento };
  } catch (e) { /* si falla, el formulario saldrá sin opciones y cargar() mostrará el error */ }
  await cargar();
})();