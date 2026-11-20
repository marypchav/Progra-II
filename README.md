# Progra-II: Cuentas de ahorro (Tareas Programadas 2 y 3)

Bases de Datos I, II semestre 2026.

Sistema de cuentas de ahorro en SQL Server con:

- **Simulación (Tarea 3):** procesa cuatro meses de operación diaria del banco a partir de un XML: crea personas, cuentas y beneficiarios, aplica movimientos y genera los estados de cuenta mensuales con intereses, comisiones, multas y cargos.
- **Portal web (Tareas 2 y 3):** el cliente entra con su usuario, administra los beneficiarios de sus cuentas y consulta sus estados de cuenta y el detalle de movimientos de cada uno.

Toda la lógica de negocio está en procedimientos almacenados. El backend (Node.js) solo llama SPs y el frontend solo llama al backend.

