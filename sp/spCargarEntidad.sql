CREATE OR ALTER PROCEDURE dbo.spCargarEntidad
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCargarEntidad
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- variables de uso general
        DECLARE @datos XML; -- contenido completo del XML

        -- tablas variables con el contenido del XML, ya tipado
        DECLARE @Persona TABLE (
            IdTipoDocuIdentidad INT
            , ValorDocumentoIdentidad VARCHAR(32)
            , Nombre VARCHAR(64)
            , FechaNacimiento DATE
            , Email VARCHAR(64)
            , Telefono1 VARCHAR(64)
            , Telefono2 VARCHAR(64)
        );

        DECLARE @Usuario TABLE (
            UserName VARCHAR(64)
            , Pass VARCHAR(64)
            , EsAdministrador BIT
            , ValorDocumento VARCHAR(32)
        );

        DECLARE @Cuenta TABLE (
            NumeroCuenta VARCHAR(20)
            , ValorDocumento VARCHAR(32)
            , IdTipoCuentaAhorro INT
            , FechaCreacion DATE
            , Saldo MONEY
        );

        DECLARE @Beneficiario TABLE (
            NumeroCuenta VARCHAR(20)
            , ValorDocumento VARCHAR(32)
            , IdParentesco INT
            , Porcentaje INT
        );

        DECLARE @EstadoCuenta TABLE (
            NumeroCuenta VARCHAR(20)
            , FechaInicio DATE
            , FechaFin DATE
            , SaldoInicial MONEY
            , SaldoMinimo MONEY
            , SaldoFinal MONEY
            , InteresesAcumulados MONEY
            , CantRetiros INT
            , CantDepositos INT
            , CantSinpeEntrantes INT
            , CantSinpeSalientes INT
        );

        DECLARE @UsuarioPuedeVer TABLE (
            UserName VARCHAR(64)
            , NumeroCuenta VARCHAR(20)
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- lee el archivo como binario (SINGLE_BLOB) y lo convierte a XML
        SELECT @datos = X.BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\no_catalogos.xml', SINGLE_BLOB) AS X;

        -- pasa cada bloque del XML a su tabla variable
        INSERT INTO @Persona (
            IdTipoDocuIdentidad
            , ValorDocumentoIdentidad
            , Nombre
            , FechaNacimiento
            , Email
            , Telefono1
            , Telefono2
        )
        SELECT T.Nodo.value('@TipoDocuIdentidad', 'INT')
            , T.Nodo.value('@ValorDocumentoIdentidad', 'VARCHAR(32)')
            , T.Nodo.value('@Nombre', 'VARCHAR(64)')
            , T.Nodo.value('@FechaNacimiento', 'DATE')
            , T.Nodo.value('@Email', 'VARCHAR(64)')
            , T.Nodo.value('@telefono1', 'VARCHAR(64)')
            , T.Nodo.value('@telefono2', 'VARCHAR(64)')
        FROM @datos.nodes('//Personas/Persona') AS T(Nodo);

        INSERT INTO @Usuario (
            UserName
            , Pass
            , EsAdministrador
            , ValorDocumento
        )
        SELECT T.Nodo.value('@User', 'VARCHAR(64)')
            , T.Nodo.value('@Pass', 'VARCHAR(64)')
            , T.Nodo.value('@EsAdministrador', 'BIT')
            , T.Nodo.value('@ValorDocId', 'VARCHAR(32)')
        FROM @datos.nodes('//Usuarios/Usuario') AS T(Nodo);

        INSERT INTO @Cuenta (
            NumeroCuenta
            , ValorDocumento
            , IdTipoCuentaAhorro
            , FechaCreacion
            , Saldo
        )
        SELECT T.Nodo.value('@NumeroCuenta', 'VARCHAR(20)')
            , T.Nodo.value('@ValorDocumentoIdentidadDelCliente', 'VARCHAR(32)')
            , T.Nodo.value('@TipoCuentaId', 'INT')
            , T.Nodo.value('@FechaCreacion', 'DATE')
            , T.Nodo.value('@Saldo', 'MONEY')
        FROM @datos.nodes('//Cuentas/Cuenta') AS T(Nodo);

        INSERT INTO @Beneficiario (
            NumeroCuenta
            , ValorDocumento
            , IdParentesco
            , Porcentaje
        )
        SELECT T.Nodo.value('@NumeroCuenta', 'VARCHAR(20)')
            , T.Nodo.value('@ValorDocumentoIdentidadBeneficiario', 'VARCHAR(32)')
            , T.Nodo.value('@IdParentezco', 'INT')
            , T.Nodo.value('@Porcentaje', 'INT')
        FROM @datos.nodes('//Beneficiarios/Beneficiario') AS T(Nodo);

        INSERT INTO @EstadoCuenta (
            NumeroCuenta
            , FechaInicio
            , FechaFin
            , SaldoInicial
            , SaldoMinimo
            , SaldoFinal
            , InteresesAcumulados
            , CantRetiros
            , CantDepositos
            , CantSinpeEntrantes
            , CantSinpeSalientes
        )
        SELECT T.Nodo.value('@NumeroCuenta', 'VARCHAR(20)')
            , T.Nodo.value('@fechaInicio', 'DATE')
            , T.Nodo.value('@fechafin', 'DATE')
            , T.Nodo.value('@saldoinicial', 'MONEY')
            , T.Nodo.value('@saldoMinimo', 'MONEY')
            , T.Nodo.value('@saldo_final', 'MONEY')
            , T.Nodo.value('@interesesAcumulados', 'MONEY')
            , T.Nodo.value('@cantRetiros', 'INT')
            , T.Nodo.value('@cantDepositos', 'INT')
            , T.Nodo.value('@cantSinpeEntrantes', 'INT')
            , T.Nodo.value('@cantSinpeSalientes', 'INT')
        FROM @datos.nodes('//Estados_de_Cuenta/Estado_de_Cuenta') AS T(Nodo);

        INSERT INTO @UsuarioPuedeVer (
            UserName
            , NumeroCuenta
        )
        SELECT T.Nodo.value('@User', 'VARCHAR(64)')
            , T.Nodo.value('@NumeroCuenta', 'VARCHAR(20)')
        FROM @datos.nodes('//Usuarios_Ver/UsuarioPuedeVer') AS T(Nodo);

        -- validaciones: todas las referencias del XML deben existir

        -- documentos de persona repetidos dentro del XML o ya cargados en la BD
        IF EXISTS (
            SELECT 1
            FROM @Persona AS XP
            GROUP BY XP.ValorDocumentoIdentidad
            HAVING (COUNT(1) > 1)
        )
            OR EXISTS (
                SELECT 1
                FROM @Persona AS XP
                INNER JOIN dbo.Persona AS P
                    ON (P.ValorDocumentoIdentidad = XP.ValorDocumentoIdentidad)
            )
        BEGIN
            SET @outResultCode = 51001;
            RETURN;
        END;

        -- usuarios cuya persona no viene en el XML
        IF EXISTS (
            SELECT 1
            FROM @Usuario AS XU
            WHERE NOT EXISTS (
                SELECT 1
                FROM @Persona AS XP
                WHERE (XP.ValorDocumentoIdentidad = XU.ValorDocumento)
            )
        )
        BEGIN
            SET @outResultCode = 51002;
            RETURN;
        END;

        -- cuentas cuyo dueño no viene en el XML
        IF EXISTS (
            SELECT 1
            FROM @Cuenta AS XC
            WHERE NOT EXISTS (
                SELECT 1
                FROM @Persona AS XP
                WHERE (XP.ValorDocumentoIdentidad = XC.ValorDocumento)
            )
        )
        BEGIN
            SET @outResultCode = 51003;
            RETURN;
        END;

        -- beneficiarios con cuenta o persona que no vienen en el XML
        IF EXISTS (
            SELECT 1
            FROM @Beneficiario AS XB
            WHERE NOT EXISTS (
                    SELECT 1
                    FROM @Cuenta AS XC
                    WHERE (XC.NumeroCuenta = XB.NumeroCuenta)
                )
                OR NOT EXISTS (
                    SELECT 1
                    FROM @Persona AS XP
                    WHERE (XP.ValorDocumentoIdentidad = XB.ValorDocumento)
                )
        )
        BEGIN
            SET @outResultCode = 51004;
            RETURN;
        END;

        -- estados de cuenta con cuenta que no viene en el XML
        IF EXISTS (
            SELECT 1
            FROM @EstadoCuenta AS XE
            WHERE NOT EXISTS (
                SELECT 1
                FROM @Cuenta AS XC
                WHERE (XC.NumeroCuenta = XE.NumeroCuenta)
            )
        )
        BEGIN
            SET @outResultCode = 51005;
            RETURN;
        END;

        -- UsuarioPuedeVer con usuario o cuenta que no vienen en el XML
        IF EXISTS (
            SELECT 1
            FROM @UsuarioPuedeVer AS XV
            WHERE NOT EXISTS (
                    SELECT 1
                    FROM @Usuario AS XU
                    WHERE (XU.UserName = XV.UserName)
                )
                OR NOT EXISTS (
                    SELECT 1
                    FROM @Cuenta AS XC
                    WHERE (XC.NumeroCuenta = XV.NumeroCuenta)
                )
        )
        BEGIN
            SET @outResultCode = 51006;
            RETURN;
        END;

        -- transacción: solo inserciones. Si una falla, no queda nada a medias.
        -- el orden respeta las llaves foráneas (padres antes que hijas)
        BEGIN TRANSACTION tCargarEntidad;

            -- personas (dueños, beneficiarios y administrador)
            INSERT INTO dbo.Persona (
                IdTipoDocuIdentidad
                , ValorDocumentoIdentidad
                , Nombre
                , FechaNacimiento
                , Email
                , Telefono1
                , Telefono2
            )
            SELECT XP.IdTipoDocuIdentidad
                , XP.ValorDocumentoIdentidad
                , XP.Nombre
                , XP.FechaNacimiento
                , XP.Email
                , XP.Telefono1
                , XP.Telefono2
            FROM @Persona AS XP;

            -- usuarios: el documento se traduce a IdPersona
            INSERT INTO dbo.Usuario (
                UserName
                , Pass
                , EsAdministrador
                , IdPersona
            )
            SELECT XU.UserName
                , XU.Pass
                , XU.EsAdministrador
                , P.IdPersona
            FROM @Usuario AS XU
            INNER JOIN dbo.Persona AS P
                ON (P.ValorDocumentoIdentidad = XU.ValorDocumento);

            -- cuentas: el documento del cliente se traduce a IdPersonaDueno
            INSERT INTO dbo.Cuenta (
                NumeroCuenta
                , IdPersonaDueno
                , IdTipoCuentaAhorro
                , FechaCreacion
                , Saldo
            )
            SELECT XC.NumeroCuenta
                , P.IdPersona
                , XC.IdTipoCuentaAhorro
                , XC.FechaCreacion
                , XC.Saldo
            FROM @Cuenta AS XC
            INNER JOIN dbo.Persona AS P
                ON (P.ValorDocumentoIdentidad = XC.ValorDocumento);

            -- beneficiarios: número de cuenta y documento se traducen a sus Ids
            INSERT INTO dbo.Beneficiario (
                IdCuenta
                , IdPersonaBeneficiario
                , IdParentesco
                , Porcentaje
            )
            SELECT C.IdCuenta
                , P.IdPersona
                , XB.IdParentesco
                , XB.Porcentaje
            FROM @Beneficiario AS XB
            INNER JOIN dbo.Cuenta AS C
                ON (C.NumeroCuenta = XB.NumeroCuenta)
            INNER JOIN dbo.Persona AS P
                ON (P.ValorDocumentoIdentidad = XB.ValorDocumento);

            -- estados de cuenta: la fecha de emisión es la fecha de fin del período
            INSERT INTO dbo.EstadoCuenta (
                IdCuenta
                , FechaInicio
                , FechaFin
                , SaldoInicial
                , SaldoFinal
                , SaldoMinimo
                , FechaEmision
                , InteresesAcumulados
                , CantRetiros
                , CantDepositos
                , CantSinpeEntrantes
                , CantSinpeSalientes
            )
            SELECT C.IdCuenta
                , XE.FechaInicio
                , XE.FechaFin
                , XE.SaldoInicial
                , XE.SaldoFinal
                , XE.SaldoMinimo
                , XE.FechaFin
                , XE.InteresesAcumulados
                , XE.CantRetiros
                , XE.CantDepositos
                , XE.CantSinpeEntrantes
                , XE.CantSinpeSalientes
            FROM @EstadoCuenta AS XE
            INNER JOIN dbo.Cuenta AS C
                ON (C.NumeroCuenta = XE.NumeroCuenta);

            -- qué cuentas puede ver cada usuario
            INSERT INTO dbo.UsuarioPuedeVer (
                IdUsuario
                , IdCuenta
            )
            SELECT U.IdUsuario
                , C.IdCuenta
            FROM @UsuarioPuedeVer AS XV
            INNER JOIN dbo.Usuario AS U
                ON (U.UserName = XV.UserName)
            INNER JOIN dbo.Cuenta AS C
                ON (C.NumeroCuenta = XV.NumeroCuenta);

        COMMIT TRANSACTION tCargarEntidad;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO
