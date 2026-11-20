/*
tablas.sql
Creación de todas las tablas de la base BDCuentaAhorros (Tareas 2 y 3).
*/

USE BDCuentaAhorros;
GO

-- 1. borra las tablas, de hijas a padres
DROP TABLE IF EXISTS dbo.Comprobante;
DROP TABLE IF EXISTS dbo.Movimiento;
DROP TABLE IF EXISTS dbo.ControlSimulacion;
DROP TABLE IF EXISTS dbo.OperacionXML;
DROP TABLE IF EXISTS dbo.EstadoCuenta;
DROP TABLE IF EXISTS dbo.Bitacora;
DROP TABLE IF EXISTS dbo.UsuarioPuedeVer;
DROP TABLE IF EXISTS dbo.Usuario;
DROP TABLE IF EXISTS dbo.Beneficiario;
DROP TABLE IF EXISTS dbo.Cuenta;
DROP TABLE IF EXISTS dbo.Persona;
DROP TABLE IF EXISTS dbo.TipoCuentaAhorro;
DROP TABLE IF EXISTS dbo.TipoMovimiento;
DROP TABLE IF EXISTS dbo.TipoOperacion;
DROP TABLE IF EXISTS dbo.TipoMoneda;
DROP TABLE IF EXISTS dbo.Parentesco;
DROP TABLE IF EXISTS dbo.TipoDocuIdentidad;
DROP TABLE IF EXISTS dbo.dbError;
GO

-- 2. catálogos. sus ids vienen del XML de catálogos, por eso no son identity

CREATE TABLE dbo.TipoDocuIdentidad (
    IdTipoDocuIdentidad INT NOT NULL
        CONSTRAINT PK_TipoDocuIdentidad PRIMARY KEY
    , Nombre VARCHAR(64) NOT NULL
);

CREATE TABLE dbo.TipoMoneda (
    IdTipoMoneda INT NOT NULL
        CONSTRAINT PK_TipoMoneda PRIMARY KEY
    , Nombre VARCHAR(64) NOT NULL
    , Simbolo NVARCHAR(5) NOT NULL -- NVARCHAR para ₡ y €
        CONSTRAINT DF_TipoMoneda_Simbolo DEFAULT (N'')
);

-- en el XML aparece como "Parentezco"
CREATE TABLE dbo.Parentesco (
    IdParentesco INT NOT NULL
        CONSTRAINT PK_Parentesco PRIMARY KEY
    , Nombre VARCHAR(32) NOT NULL
);

-- reglas de cada tipo de cuenta. los montos están en la moneda del tipo
CREATE TABLE dbo.TipoCuentaAhorro (
    IdTipoCuentaAhorro INT NOT NULL
        CONSTRAINT PK_TipoCuentaAhorro PRIMARY KEY
    , Nombre VARCHAR(64) NOT NULL
    , IdTipoMoneda INT NOT NULL
        CONSTRAINT FK_TipoCuentaAhorro_TipoMoneda REFERENCES dbo.TipoMoneda (IdTipoMoneda)
    , SaldoMinimo MONEY NOT NULL -- si el saldo mínimo del mes es menor, se cobra multa
    , MultaSaldoMin MONEY NOT NULL
    , CargoMensualServicio MONEY NOT NULL
    , MaxOperHumanoGratis INT NOT NULL -- operaciones en ventana por mes sin comisión
    , MaxOperAutomaticoGratis INT NOT NULL -- operaciones en ATM por mes sin comisión
    , ComisionHumanoExceso MONEY NOT NULL -- por cada operación en ventana sobre el máximo
    , ComisionAutomaticoExceso MONEY NOT NULL -- por cada operación en ATM sobre el máximo
    , TasaInteresAnual DECIMAL(5, 2) NOT NULL -- en porcentaje; al cierre se divide entre 12
    , MaxDiarioSinpeSinComision MONEY NOT NULL -- suma de envíos sinpe por día sin comisión
        CONSTRAINT DF_TipoCuentaAhorro_MaxDiarioSinpeSinComision DEFAULT (0)
    , ComisionSinpeExceso MONEY NOT NULL -- por cada envío que supere el máximo diario
        CONSTRAINT DF_TipoCuentaAhorro_ComisionSinpeExceso DEFAULT (0)
);

CREATE TABLE dbo.TipoMovimiento (
    IdTipoMovimiento INT NOT NULL
        CONSTRAINT PK_TipoMovimiento PRIMARY KEY
    , Nombre VARCHAR(64) NOT NULL -- los movimientos del XML de operaciones se buscan por nombre
        CONSTRAINT UQ_TipoMovimiento_Nombre UNIQUE
    , Accion VARCHAR(16) NOT NULL -- Credito suma al saldo, Debito resta
        CONSTRAINT CK_TipoMovimiento_Accion CHECK (Accion IN ('Credito', 'Debito'))
    , FlagGeneraComprobante BIT NOT NULL -- 1 = se envía comprobante al email del dueño
);

-- operaciones que se registran en la bitácora
CREATE TABLE dbo.TipoOperacion (
    IdTipoOperacion INT NOT NULL
        CONSTRAINT PK_TipoOperacion PRIMARY KEY
    , Nombre VARCHAR(64) NOT NULL
);
GO

-- 3. personas, cuentas y beneficiarios

CREATE TABLE dbo.Persona (
    IdPersona INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Persona PRIMARY KEY
    , IdTipoDocuIdentidad INT NOT NULL
        CONSTRAINT FK_Persona_TipoDocuIdentidad REFERENCES dbo.TipoDocuIdentidad (IdTipoDocuIdentidad)
    , ValorDocumentoIdentidad VARCHAR(32) NOT NULL
        CONSTRAINT UQ_Persona_ValorDocumentoIdentidad UNIQUE
        CONSTRAINT CK_Persona_DocumentoNumerico CHECK (ValorDocumentoIdentidad NOT LIKE '%[^0-9]%')
    , Nombre VARCHAR(64) NOT NULL
    , FechaNacimiento DATE NOT NULL
    , Email VARCHAR(64) NOT NULL
    , Telefono1 VARCHAR(64) NOT NULL
    , Telefono2 VARCHAR(64) NOT NULL
);

CREATE TABLE dbo.Cuenta (
    IdCuenta INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Cuenta PRIMARY KEY
    , NumeroCuenta VARCHAR(20) NOT NULL -- en el XML de movimientos aparece como CodigoCuenta
        CONSTRAINT UQ_Cuenta_NumeroCuenta UNIQUE
    , IdPersonaDueno INT NOT NULL
        CONSTRAINT FK_Cuenta_Persona REFERENCES dbo.Persona (IdPersona)
    , IdTipoCuentaAhorro INT NOT NULL
        CONSTRAINT FK_Cuenta_TipoCuentaAhorro REFERENCES dbo.TipoCuentaAhorro (IdTipoCuentaAhorro)
    , FechaCreacion DATE NOT NULL -- de aquí salen las fechas de cierre de cada estado de cuenta
    , Saldo MONEY NOT NULL -- saldo actual; se actualiza con cada movimiento
);

CREATE TABLE dbo.Beneficiario (
    IdBeneficiario INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Beneficiario PRIMARY KEY
    , IdCuenta INT NOT NULL
        CONSTRAINT FK_Beneficiario_Cuenta REFERENCES dbo.Cuenta (IdCuenta)
    , IdPersonaBeneficiario INT NOT NULL
        CONSTRAINT FK_Beneficiario_Persona REFERENCES dbo.Persona (IdPersona)
    , IdParentesco INT NOT NULL
        CONSTRAINT FK_Beneficiario_Parentesco REFERENCES dbo.Parentesco (IdParentesco)
    , Porcentaje INT NOT NULL
        CONSTRAINT CK_Beneficiario_Porcentaje CHECK ((Porcentaje >= 0) AND (Porcentaje <= 100))
    , FlagActivo BIT NOT NULL -- borrado lógico: 0 = eliminado
        CONSTRAINT DF_Beneficiario_FlagActivo DEFAULT (1)
    , FechaDesactivacion DATETIME NULL
);

-- una persona solo puede ser beneficiario activo una vez por cuenta
CREATE UNIQUE INDEX UQ_Beneficiario_CuentaPersonaActivo
    ON dbo.Beneficiario (IdCuenta, IdPersonaBeneficiario)
    WHERE (FlagActivo = 1);
GO

-- 4. usuarios del portal y bitácora

CREATE TABLE dbo.Usuario (
    IdUsuario INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Usuario PRIMARY KEY
    , UserName VARCHAR(64) NOT NULL
        CONSTRAINT UQ_Usuario_UserName UNIQUE
    , Pass VARCHAR(64) NOT NULL
    , EsAdministrador BIT NOT NULL -- 1 = puede ver todas las cuentas
    , IdPersona INT NULL -- NULL en un administrador que no es cliente
        CONSTRAINT FK_Usuario_Persona REFERENCES dbo.Persona (IdPersona)
);

-- cuentas que puede consultar cada usuario no administrador
CREATE TABLE dbo.UsuarioPuedeVer (
    IdUsuarioPuedeVer INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_UsuarioPuedeVer PRIMARY KEY
    , IdUsuario INT NOT NULL
        CONSTRAINT FK_UsuarioPuedeVer_Usuario REFERENCES dbo.Usuario (IdUsuario)
    , IdCuenta INT NOT NULL
        CONSTRAINT FK_UsuarioPuedeVer_Cuenta REFERENCES dbo.Cuenta (IdCuenta)
    , CONSTRAINT UQ_UsuarioPuedeVer_UsuarioCuenta UNIQUE (IdUsuario, IdCuenta)
);

CREATE TABLE dbo.Bitacora (
    IdBitacora INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Bitacora PRIMARY KEY
    , IdUsuario INT NOT NULL
        CONSTRAINT FK_Bitacora_Usuario REFERENCES dbo.Usuario (IdUsuario)
    , IdTipoOperacion INT NOT NULL
        CONSTRAINT FK_Bitacora_TipoOperacion REFERENCES dbo.TipoOperacion (IdTipoOperacion)
    , IP VARCHAR(64) NULL
    , DatosAntes NVARCHAR(MAX) NULL -- JSON con los datos antes del cambio
    , DatosDespues NVARCHAR(MAX) NULL -- JSON con los datos después del cambio
    , FechaHora DATETIME NOT NULL
        CONSTRAINT DF_Bitacora_FechaHora DEFAULT (GETDATE())
);

CREATE INDEX IX_Bitacora_Usuario
    ON dbo.Bitacora (IdUsuario, FechaHora);
GO

-- 5. estados de cuenta

CREATE TABLE dbo.EstadoCuenta (
    IdEstadoCuenta INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_EstadoCuenta PRIMARY KEY
    , IdCuenta INT NOT NULL
        CONSTRAINT FK_EstadoCuenta_Cuenta REFERENCES dbo.Cuenta (IdCuenta)
    , NumeroPeriodo INT NOT NULL -- 1 = el que abre el trigger; las fechas se calculan desde FechaCreacion
    , FechaInicio DATE NOT NULL
    , FechaFin DATE NOT NULL -- día en que se cierra
    , FechaEmision DATE NULL -- se llena al cerrar
    , SaldoInicial MONEY NOT NULL
    , SaldoFinal MONEY NOT NULL -- se actualiza con cada movimiento
    , SaldoMinimo MONEY NULL -- NULL en el primer período hasta el primer movimiento
    , InteresesAcumulados MONEY NOT NULL
        CONSTRAINT DF_EstadoCuenta_InteresesAcumulados DEFAULT (0)
    , CantOperATM INT NOT NULL
        CONSTRAINT DF_EstadoCuenta_CantOperATM DEFAULT (0)
    , CantOperVentana INT NOT NULL -- cajero humano
        CONSTRAINT DF_EstadoCuenta_CantOperVentana DEFAULT (0)
    , CantOperSinpe INT NOT NULL
        CONSTRAINT DF_EstadoCuenta_CantOperSinpe DEFAULT (0)
    , FlagAbierto BIT NOT NULL -- 1 = estado vigente, 0 = cerrado
        CONSTRAINT DF_EstadoCuenta_FlagAbierto DEFAULT (1)
    , CONSTRAINT UQ_EstadoCuenta_CuentaPeriodo UNIQUE (IdCuenta, NumeroPeriodo)
);

-- para encontrar rápido los estados que cierran en una fecha
CREATE INDEX IX_EstadoCuenta_Cierre
    ON dbo.EstadoCuenta (FlagAbierto, FechaFin);
GO

-- 6. simulación

-- staging del XML de operaciones: una fila por nodo, con PK para poder
-- reiniciar la simulación desde el último nodo procesado
CREATE TABLE dbo.OperacionXML (
    IdOperacionXML INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_OperacionXML PRIMARY KEY
    , FechaOperacion DATE NOT NULL
    , Orden INT NOT NULL -- 1 Persona, 2 Cuenta, 3 Beneficiario, 4 Usuario, 5 UsuarioPuedeVer, 6 Movimientos
    , TipoNodo VARCHAR(32) NOT NULL
    , Nodo XML NOT NULL -- el nodo completo, con sus atributos
);

CREATE INDEX IX_OperacionXML_Fecha
    ON dbo.OperacionXML (FechaOperacion, Orden, IdOperacionXML);

-- control de la simulación: una fila por fecha procesada.
-- evita correr una fecha dos veces y guarda la última PK procesada
CREATE TABLE dbo.ControlSimulacion (
    IdControlSimulacion INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_ControlSimulacion PRIMARY KEY
    , FechaOperacion DATE NOT NULL
        CONSTRAINT UQ_ControlSimulacion_FechaOperacion UNIQUE
    , UltimoIdOperacionXML INT NULL -- último nodo aplicado de esa fecha
    , FlagTerminado BIT NOT NULL
        CONSTRAINT DF_ControlSimulacion_FlagTerminado DEFAULT (0)
    , FechaInicioProceso DATETIME NOT NULL
        CONSTRAINT DF_ControlSimulacion_FechaInicioProceso DEFAULT (GETDATE())
    , FechaFinProceso DATETIME NULL
);
GO

-- 7. movimientos y comprobantes

CREATE TABLE dbo.Movimiento (
    IdMovimiento INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Movimiento PRIMARY KEY
    , IdCuenta INT NOT NULL
        CONSTRAINT FK_Movimiento_Cuenta REFERENCES dbo.Cuenta (IdCuenta)
    , IdEstadoCuenta INT NOT NULL -- estado de cuenta al que pertenece
        CONSTRAINT FK_Movimiento_EstadoCuenta REFERENCES dbo.EstadoCuenta (IdEstadoCuenta)
    , IdTipoMovimiento INT NOT NULL
        CONSTRAINT FK_Movimiento_TipoMovimiento REFERENCES dbo.TipoMovimiento (IdTipoMovimiento)
    , IdOperacionXML INT NULL -- nodo del XML que lo generó; NULL en los movimientos del cierre
        CONSTRAINT FK_Movimiento_OperacionXML REFERENCES dbo.OperacionXML (IdOperacionXML)
    , Fecha DATE NOT NULL
    , Monto MONEY NOT NULL -- siempre positivo; la Accion del tipo dice si suma o resta
    , NuevoSaldo MONEY NOT NULL -- saldo después de aplicar el movimiento
    , Descripcion NVARCHAR(128) NOT NULL -- NVARCHAR por las tildes del XML
    , PostTime DATETIME NOT NULL
        CONSTRAINT DF_Movimiento_PostTime DEFAULT (GETDATE())
);

-- para el detalle del portal (orden cronológico por estado)
CREATE INDEX IX_Movimiento_Estado
    ON dbo.Movimiento (IdEstadoCuenta, Fecha, IdMovimiento);

-- para sumar los envíos sinpe de una cuenta en un día
CREATE INDEX IX_Movimiento_CuentaFecha
    ON dbo.Movimiento (IdCuenta, Fecha, IdTipoMovimiento);

-- comprobantes enviados al email del dueño
CREATE TABLE dbo.Comprobante (
    IdComprobante INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Comprobante PRIMARY KEY
    , IdMovimiento INT NOT NULL
        CONSTRAINT FK_Comprobante_Movimiento REFERENCES dbo.Movimiento (IdMovimiento)
        CONSTRAINT UQ_Comprobante_Movimiento UNIQUE -- un comprobante por movimiento
    , Email VARCHAR(64) NOT NULL -- email del dueño de la cuenta
    , FechaEnvio DATETIME NOT NULL
        CONSTRAINT DF_Comprobante_FechaEnvio DEFAULT (GETDATE())
    , Detalle NVARCHAR(256) NOT NULL -- texto del comprobante
);
GO

-- 8. errores que registran los SPs en su CATCH
CREATE TABLE dbo.dbError (
    ErrorID INT IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_dbError PRIMARY KEY
    , UserName VARCHAR(100) NULL
    , ErrorNumber INT NULL
    , ErrorState INT NULL
    , ErrorSeverity INT NULL
    , ErrorLine INT NULL
    , ErrorProcedure VARCHAR(MAX) NULL
    , ErrorMessage VARCHAR(MAX) NULL
    , ErrorDateTime DATETIME NULL
);
GO
